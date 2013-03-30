
#pragma once

#include <mach/mach_time.h>

// Usage: Get mach_timebase_info_data_t using:
// mach_timebase_info_data_t info;
// kern_return_t kret = mach_timebase_info(&info);

uint64_t convert_from_nanos_to_mach_timebase(uint64_t nanos, mach_timebase_info_data_t *info);
uint64_t convert_from_mach_timebase_to_nanos(uint64_t mach_time, mach_timebase_info_data_t *info);

