
#include "debug.h"

#import "Config.h"
#import "Mouse.h"

#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>

BOOL is_dumping;

static int maxHz = -1;
static int numHz = 0;
static int sumHz = 0;

std::vector<void *> logs;
pthread_mutex_t log_mutex = PTHREAD_MUTEX_INITIALIZER;

void debug_register_event(kext_event_t *event) {
    static long long lastTimestamp = 0;

    if (lastTimestamp != 0) {
        float deltaTimestamp = event->base.timestamp - lastTimestamp; // timestamp is ns

        int hz = (int) (1000000000 / deltaTimestamp);

        sumHz += hz;
        numHz++;

        if (maxHz < hz) {
            maxHz = hz;
        }
    }

    lastTimestamp = event->base.timestamp;
}

void debug_end() {
    is_dumping = 1;

    if (!logs.empty()) {
        NSLog(@"Dumping log");
    } else {
        NSLog(@"No logs to dump");
    }

    std::vector<void *>::iterator it;
    for (it = logs.begin(); it != logs.end(); it++) {
        NSString *log = (NSString *)*it;
        if (log == nil) {
            NSLog(@"log nil, should never happen");
            exit(1);
        }
        NSLog(@"%@", log);
        [log release];
    }

    if ([[Config instance] timingsEnabled]) {
        NSLog(@"outer average: %f", (outersum / outernum));
    }

    if (!logs.empty()) {
        NSLog(@"Dumping complete");
    }

    NSLog(@"Number of lost kext events: %d", totalNumberOfLostEvents);

    NSLog(@"Number of lost clicks: %d", [sMouseSupervisor numClickEvents]);

    NSLog(@"Summary: Average Hz: %.2f, Maximum Hz: %d", (sumHz / (float)numHz), maxHz);
}

