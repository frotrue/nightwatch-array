#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <pdh.h>
#include <pdhmsg.h>
#include <algorithm>
#include <cmath>
#include <string>

// Match Task Manager's process metric: the busiest engine across adapters.
// Vulkan may run on Graphics_1 or Compute rather than the engine named 3D.
// Engine percentages overlap, so summing them would overstate utilization.
inline double gpu_usage(const PDH_FMT_COUNTERVALUE_ITEM_W* items, DWORD count,
                        const std::wstring& process_prefix) {
    double usage = -1.0;
    for (DWORD i = 0; i < count; ++i) {
        const auto& value = items[i].FmtValue;
        if (!items[i].szName || std::wstring(items[i].szName).compare(0, process_prefix.size(), process_prefix) != 0)
            continue;
        if ((value.CStatus == PDH_CSTATUS_VALID_DATA || value.CStatus == PDH_CSTATUS_NEW_DATA)
            && std::isfinite(value.doubleValue) && value.doubleValue >= 0.0)
            usage = std::max(usage, std::min(value.doubleValue, 100.0));
    }
    return usage;
}
