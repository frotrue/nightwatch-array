// Optional, isolated Windows telemetry. No engine threads or gameplay state.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <pdh.h>
#include <pdhmsg.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

static bool cpu_time(HANDLE process, unsigned long long& result) {
    FILETIME created{}, exited{}, kernel{}, user{};
    if (!GetProcessTimes(process, &created, &exited, &kernel, &user)) return false;
    ULARGE_INTEGER k{}, u{};
    k.LowPart = kernel.dwLowDateTime; k.HighPart = kernel.dwHighDateTime;
    u.LowPart = user.dwLowDateTime; u.HighPart = user.dwHighDateTime;
    result = k.QuadPart + u.QuadPart;
    return true;
}

int main(int argc, char** argv) {
    if (argc != 2) return 2;
    const DWORD pid = strtoul(argv[1], nullptr, 10);
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, pid);
    if (!process) return 3;
    SetPriorityClass(GetCurrentProcess(), BELOW_NORMAL_PRIORITY_CLASS);
    PDH_HQUERY query = nullptr;
    PDH_HCOUNTER counter = nullptr;
    if (PdhOpenQueryW(nullptr, 0, &query) == ERROR_SUCCESS) {
        // English paths work on localized Windows installations. Wildcards also
        // discover engines created after monitoring was enabled.
        if (PdhAddEnglishCounterW(query, L"\\GPU Engine(*)\\Utilization Percentage", 0, &counter) != ERROR_SUCCESS)
            counter = nullptr;
        if (counter) PdhCollectQueryData(query);
    }
    const std::wstring prefix = L"pid_" + std::to_wstring(pid) + L"_";
    const DWORD cores = std::max<DWORD>(1, GetActiveProcessorCount(ALL_PROCESSOR_GROUPS));
    LARGE_INTEGER frequency{}, previous{}, now{};
    QueryPerformanceFrequency(&frequency);
    QueryPerformanceCounter(&previous);
    unsigned long long previous_cpu = 0;
    bool previous_valid = cpu_time(process, previous_cpu);
    while (WaitForSingleObject(process, 1000) == WAIT_TIMEOUT) {
        QueryPerformanceCounter(&now);
        unsigned long long current_cpu = 0;
        const bool current_valid = cpu_time(process, current_cpu);
        const double elapsed = double(now.QuadPart - previous.QuadPart) / frequency.QuadPart;
        const double cpu = previous_valid && current_valid && current_cpu >= previous_cpu && elapsed > 0
            ? std::clamp(double(current_cpu - previous_cpu) / 1e7 / elapsed / cores * 100.0, 0.0, 100.0) : -1.0;
        previous = now; previous_cpu = current_cpu; previous_valid = current_valid;
        double gpu = -1.0;
        if (counter && PdhCollectQueryData(query) == ERROR_SUCCESS) {
            DWORD bytes = 0, count = 0;
            const DWORD format = PDH_FMT_DOUBLE | PDH_FMT_NOCAP100;
            if (PdhGetFormattedCounterArrayW(counter, format, &bytes, &count, nullptr) == PDH_MORE_DATA && bytes < 16 * 1024 * 1024) {
                std::vector<unsigned char> storage(bytes);
                auto items = reinterpret_cast<PDH_FMT_COUNTERVALUE_ITEM_W*>(storage.data());
                if (PdhGetFormattedCounterArrayW(counter, format, &bytes, &count, items) == ERROR_SUCCESS) {
                    for (DWORD i = 0; i < count; ++i) {
                        const std::wstring name(items[i].szName);
                        const auto& value = items[i].FmtValue;
                        if (name.compare(0, prefix.size(), prefix) == 0 && name.find(L"engtype_3D") != std::wstring::npos
                            && (value.CStatus == PDH_CSTATUS_VALID_DATA || value.CStatus == PDH_CSTATUS_NEW_DATA)
                            && std::isfinite(value.doubleValue)) {
                            // Busiest 3D engine for this PID; never sum unrelated
                            // engines/adapters into a misleading percentage.
                            gpu = std::max(gpu, std::clamp(value.doubleValue, 0.0, 100.0));
                        }
                    }
                }
            }
        }
        char line[128];
        const int length = sprintf_s(line, "{\"cpu\":%.2f,\"gpu\":%.2f}\n", cpu, gpu);
        DWORD written = 0;
        if (!WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), line, length, &written, nullptr) || written != DWORD(length)) break;
    }
    if (query) PdhCloseQuery(query);
    CloseHandle(process);
    return 0;
}
