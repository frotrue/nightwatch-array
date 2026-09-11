#define WIN32_LEAN_AND_MEAN
#include "gpu_usage.h"
#include <cstdio>
#include <limits>

static PDH_FMT_COUNTERVALUE_ITEM_W sample(const wchar_t* name, double value,
                                         DWORD status = PDH_CSTATUS_VALID_DATA) {
    PDH_FMT_COUNTERVALUE_ITEM_W item{};
    item.szName = const_cast<wchar_t*>(name);
    item.FmtValue.CStatus = status;
    item.FmtValue.doubleValue = value;
    return item;
}

int main() {
    const std::wstring prefix = L"pid_42_";
    PDH_FMT_COUNTERVALUE_ITEM_W rows[] = {
        sample(L"pid_42_luid_A_phys_0_eng_0_engtype_3D", 0.0),
        sample(L"pid_42_luid_A_phys_0_eng_9_engtype_Graphics_1", 17.0),
        sample(L"pid_42_luid_A_phys_0_eng_5_engtype_Copy", 1.0),
        sample(L"pid_420_luid_A_phys_0_eng_0_engtype_3D", 99.0),
        sample(L"pid_7_luid_A_phys_0_eng_0_engtype_3D", 100.0),
    };
    int failures = 0;
    auto check = [&](bool valid, const char* message) {
        if (!valid) { std::fprintf(stderr, "GPU_USAGE_FAIL: %s\n", message); ++failures; }
    };
    check(gpu_usage(rows, 5, prefix) == 17.0, "Graphics_1 load must replace idle 3D, without summing Copy or other PIDs");
    rows[0].FmtValue.doubleValue = 25.0;
    check(gpu_usage(rows, 5, prefix) == 25.0, "OpenGL 3D engine remains supported");
    rows[0] = sample(L"pid_42_luid_B_phys_0_eng_1_engtype_Compute_0", 35.0, PDH_CSTATUS_NEW_DATA);
    check(gpu_usage(rows, 5, prefix) == 35.0, "include Compute and other adapters without summing");
    rows[0].FmtValue.CStatus = PDH_CSTATUS_INVALID_DATA;
    check(gpu_usage(rows, 5, prefix) == 17.0, "invalid status cannot mask valid engines");
    rows[0] = sample(L"pid_42_luid_A_phys_0_eng_0_engtype_3D", 0.0);
    check(gpu_usage(rows, 1, prefix) == 0.0, "valid idle is zero, not unavailable");
    rows[0].FmtValue.doubleValue = std::numeric_limits<double>::quiet_NaN();
    check(gpu_usage(rows, 1, prefix) == -1.0, "NaN is unavailable");
    rows[0].FmtValue.doubleValue = std::numeric_limits<double>::infinity();
    check(gpu_usage(rows, 1, prefix) == -1.0, "infinity is unavailable");
    rows[0].FmtValue.doubleValue = -1.0;
    check(gpu_usage(rows, 1, prefix) == -1.0, "negative counter is unavailable");
    rows[0].FmtValue.doubleValue = 120.0;
    check(gpu_usage(rows, 1, prefix) == 100.0, "percentage stays bounded");
    check(gpu_usage(rows, 0, prefix) == -1.0, "missing counters are unavailable");
    check(gpu_usage(rows, 5, L"pid_9_") == -1.0, "missing PID cannot borrow another process's usage");
    if (!failures) std::puts("GPU_USAGE_TEST_PASS");
    return failures ? 1 : 0;
}
