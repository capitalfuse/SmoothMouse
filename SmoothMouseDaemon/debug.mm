
#include "debug.h"

#import "Config.h"
#import "Mouse.h"

#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>

BOOL is_dumping;

static int maxHz = -1;
static int numHz = 0;
static int sumHz = 0;

void debug_register_event(mouse_event_t *event) {
    static long long lastTimestamp = 0;

    if (lastTimestamp != 0) {
        float deltaTimestamp = event->timestamp - lastTimestamp; // timestamp is ns

        int hz = (int) (1000000000 / deltaTimestamp);

        sumHz += hz;
        numHz++;

        if (maxHz < hz) {
            maxHz = hz;
        }
    }

    lastTimestamp = event->timestamp;
}

void debug_end() {
    is_dumping = 1;

    if ([logs count] > 0) {
        NSLog(@"Dumping log");
    } else {
        NSLog(@"No logs to dump");
    }

    for (NSString *log in logs) {
        if (log == nil) {
            NSLog(@"log nil, should never happen");
            exit(1);
        }
        NSLog(@"%@", log);
    }

    if ([[Config instance] timingsEnabled]) {
        NSLog(@"outer average: %f", (outersum / outernum));
    }

    if ([logs count] > 0) {
        NSLog(@"Dumping complete");
    }

    NSLog(@"Number of lost kext events: %d", totalNumberOfLostEvents);

    NSLog(@"Number of lost clicks: %d", [sMouseSupervisor numClickEvents]);

    NSLog(@"Summary: Average Hz: %.2f, Maximum Hz: %d", (sumHz / (float)numHz), maxHz);
}

