
#pragma once

#include "KextProtocol.h"
#import "Config.h"
#include <mach/mach_time.h>

extern double start, end, e1, e2, outerstart, outerend, outersum, outernum;
extern NSMutableArray* logs;
extern BOOL is_dumping;

#define GET_TIME() (mach_absolute_time()/1000.0);
#define LOG(format, ...) \
    if (!is_dumping) { \
        if([[Config instance] memoryLoggingEnabled]) { \
            NSString *s = [NSString stringWithFormat: format, ##__VA_ARGS__]; \
            if (s != nil) { \
                @synchronized(logs) { \
                    [logs addObject: s]; \
                } \
            } else { \
                NSLog(@"log string nil! (%s, %d, %@)", __FILE__, __LINE__, format); \
            } \
        } else { \
            NSLog(format, ##__VA_ARGS__); \
        } \
    }

void debug_register_event(mouse_event_t *event);
void debug_end();

