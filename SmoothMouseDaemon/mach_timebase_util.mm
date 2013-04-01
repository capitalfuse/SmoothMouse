
#import "debug.h"
#import "mach_timebase_util.h"

uint64_t convert_from_nanos_to_mach_timebase(uint64_t nanos, mach_timebase_info_data_t *info)
{
    Float64 timebase = static_cast<Float64>(info->denom) / static_cast<Float64>(info->numer);
    uint64_t mach_time = nanos * timebase;
    //NSLog(@"convert_from_nanos_to_mach_timebase: %llu => %llu", nanos, mach_time);
    return mach_time;
}

uint64_t convert_from_mach_timebase_to_nanos(uint64_t mach_time, mach_timebase_info_data_t *info)
{
    Float64 timebase = static_cast<Float64>(info->numer) / static_cast<Float64>(info->denom);
    uint64_t nanos = mach_time * timebase;
    //NSLog(@"convert_from_mach_timebase_to_nanos: %llu => %llu", mach_time, nanos);
    return nanos;
}

