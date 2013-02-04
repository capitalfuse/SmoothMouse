
#pragma once

#include "kextdaemon.h"

#include <mach/mach_time.h>

extern BOOL is_memory;
extern BOOL is_dumping;
extern BOOL is_timings;
extern double start, end, e1, e2, outerstart, outerend, outersum, outernum;
extern NSMutableArray* logs;

#define GET_TIME() (mach_absolute_time() / 1000.0);
#define LOG(format, ...) if (!is_dumping) { if(is_memory) {[logs addObject: [NSString stringWithFormat:format, ##__VA_ARGS__]];} else {NSLog(format, ##__VA_ARGS__); } }

void debug_register_event(mouse_event_t *event);
void debug_end();
