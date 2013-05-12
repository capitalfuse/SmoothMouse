
#pragma once

#include "KextProtocol.h"
#import "Config.h"
#include <mach/mach_time.h>
#include <pthread.h>
#include <vector>

extern double start, end, e1, e2, outerstart, outerend, outersum, outernum;
extern std::vector<void *> logs;
extern BOOL is_dumping;
extern pthread_mutex_t log_mutex;

#define GET_TIME() (mach_absolute_time()/1000.0);
#define LOG(format, ...) \
    if (!is_dumping) { \
        if([[Config instance] memoryLoggingEnabled]) { \
            NSString *s = [NSString stringWithFormat: format, ##__VA_ARGS__]; \
            [s retain]; \
            if (s != nil) { \
                pthread_mutex_lock(&log_mutex); \
                logs.push_back(s); \
                pthread_mutex_unlock(&log_mutex); \
            } else { \
                NSLog(@"log string nil! (%s, %d, %@)", __FILE__, __LINE__, format); \
            } \
        } else { \
            NSLog(format, ##__VA_ARGS__); \
        } \
    }

void debug_register_event(mouse_event_t *event);
void debug_end();

