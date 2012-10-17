
#include "debug.h"

#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>

static int maxHz = -1;
static int numHz = 0;
static int sumHz = 0;

void debug_log(mouse_event_t *event, float calcdx, float calcdy) {
    static long long lastTimestamp = 0;
    static CGPoint lastPoint = { 0, 0 };
    
    CGEventRef evt = CGEventCreate(NULL);
    CGPoint point = CGEventGetLocation(evt);
    
    if (lastTimestamp != 0) {
        NSLog(@"Actual system mouse position: %f x %f", point.x, point.y);
        
        float deltaTimestamp = event->timestamp - lastTimestamp; // timestamp is ns
        
        float actualdx = point.x - lastPoint.x;
        float actualdy = point.y - lastPoint.y;
        
        int hz = (int) (1000000000 / deltaTimestamp);

        sumHz += hz;
        numHz++;
        
        if (maxHz < hz) {
            maxHz = hz;
        }

        BOOL inconsistencyDetected = (abs(actualdx - calcdx) > 0.1) || (abs(actualdy - calcdy) > 0.1);
        
        NSLog(@"Kext: %d ⨉ %d \tCalc: %.2f ⨉ %.2f \tMove: %.2f ⨉ %.2f \t%d Hz	%s",
              event->dx,
              event->dy,
              calcdx,
              calcdy,
              actualdx,
              actualdy,
              hz,
              inconsistencyDetected ? "INCONSISTENCY!" : "");
    }
    
    lastTimestamp = event->timestamp;
    lastPoint = point;
    
    CFRelease(evt);
}

void debug_end() {
    NSLog(@"Summary: Average Hz: %.2f, Maximum Hz: %d", (sumHz / (float)numHz), maxHz);
}

