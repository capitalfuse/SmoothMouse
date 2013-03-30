
#include "prio.h"

#import <mach/mach.h>
#import <mach/mach_time.h>
#include <pthread.h>

static BOOL set_high_prio_pthread() {
    struct sched_param sp;

    memset(&sp, 0, sizeof(struct sched_param));

    sp.sched_priority = sched_get_priority_max(SCHED_RR);

    if (pthread_setschedparam(pthread_self(), SCHED_RR, &sp)  == -1) {
        NSLog(@"call to pthread_setschedparam failed");
        return NO;
    }

    NSLog(@"Thread prio set to highest (%u)", sp.sched_priority);

    return YES;
}

static inline uint64_t convert_from_nanos_to_mach_timebase(uint64_t nanos, mach_timebase_info_data_t *info)
{
    Float64 timebase = static_cast<Float64>(info->denom) / static_cast<Float64>(info->numer);
    uint64_t mach_time = nanos * timebase;
    //NSLog(@"convert_from_nanos_to_mach_timebase: %llu => %llu", nanos, mach_time);
    return mach_time;
}

static inline uint64_t convert_from_mach_timebase_to_nanos(uint64_t mach_time, mach_timebase_info_data_t *info)
{
    Float64 timebase = static_cast<Float64>(info->numer) / static_cast<Float64>(info->denom);
    uint64_t nanos = mach_time * timebase;
    //NSLog(@"convert_from_mach_timebase_to_nanos: %llu => %llu", mach_time, nanos);
    return nanos;
}

static BOOL set_realtime_prio() {
    mach_timebase_info_data_t info;
    kern_return_t kret = mach_timebase_info(&info);
    if (kret != KERN_SUCCESS) {
        NSLog(@"call to mach_timebase_info failed: %d", kret);
    }

    /* See:
     http://developer.apple.com/library/mac/#documentation/Darwin/Conceptual/KernelProgramming/scheduler/scheduler.html
     http://developer.apple.com/library/mac/#qa/qa1398/_index.html
     */

#define MS_TO_NANOS(ms) ((ms) * 1000000)

    struct thread_time_constraint_policy ttcpolicy;
    // 500hz mouse = 2ms
    ttcpolicy.period        = (uint32_t) convert_from_nanos_to_mach_timebase(MS_TO_NANOS(2), &info);
    ttcpolicy.computation   = (uint32_t) convert_from_nanos_to_mach_timebase(50000, &info);
    ttcpolicy.constraint    = (uint32_t) convert_from_nanos_to_mach_timebase(200000, &info);
    ttcpolicy.preemptible   = 1;

#undef MS_TO_NANOS

    NSLog(@"period: %u, computation: %u, constraint: %u (all in mach timebase), preemtible: %u",
          ttcpolicy.period,
          ttcpolicy.computation,
          ttcpolicy.constraint,
          ttcpolicy.preemptible);

    thread_port_t thread_port = pthread_mach_thread_np(pthread_self());

    kret = thread_policy_set(thread_port,
                             THREAD_TIME_CONSTRAINT_POLICY, (thread_policy_t) &ttcpolicy,
                             THREAD_TIME_CONSTRAINT_POLICY_COUNT);

    if (kret != KERN_SUCCESS) {
        NSLog(@"call to thread_policy_set failed: %d", kret);
        return NO;
    }

    NSLog(@"Time constraint policy set");
    
    return YES;
}

BOOL prio_set_realtime() {
    BOOL ok = set_high_prio_pthread();
    if (ok) {
        ok = set_realtime_prio();
    }
    return ok;
}
