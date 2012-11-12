
#include "debug.h"

#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>

static int maxHz = -1;
static int numHz = 0;
static int sumHz = 0;

void debug_log(mouse_event_t *event, CGPoint currentPos, float calcdx, float calcdy) {
    static long long lastTimestamp = 0;
    static CGPoint lastPos = { 0, 0 };
    
    if (lastTimestamp != 0) {
        //NSLog(@"Actual system mouse position: %f x %f", currentPos.x, currentPos.y);
        
        float deltaTimestamp = event->timestamp - lastTimestamp; // timestamp is ns
        
        float actualdx = currentPos.x - lastPos.x;
        float actualdy = currentPos.y - lastPos.y;
        
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
    lastPos = currentPos;
}

void debug_end() {
    NSLog(@"Summary: Average Hz: %.2f, Maximum Hz: %d", (sumHz / (float)numHz), maxHz);
}

