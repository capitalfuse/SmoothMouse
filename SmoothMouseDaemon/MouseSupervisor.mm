
#import "MouseSupervisor.h"
#import "debug.h"

#include <pthread.h>

MouseSupervisor *sMouseSupervisor;

static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;

@implementation MouseSupervisor

- (id)init
{
    self = [super init];
    if (self) {
        clickEvents = 0;
        clickEventsZeroLevel = 0;
    }
    return self;
}

- (void) pushMoveEvent: (int) deltaX : (int) deltaY {
    pthread_mutex_lock(&mutex);
    moveEvents.push(deltaX);
    moveEvents.push(deltaY);
    //LOG(@"SUPERVISOR: Pushed %d, %d", deltaX, deltaY);
    pthread_mutex_unlock(&mutex);
}

- (BOOL) popMoveEvent: (int) deltaX :(int)deltaY {
    int storedDeltaSumX = 0;
    int storedDeltaSumY = 0;
    //LOG(@"SUPERVISOR: Searching for %d %d", deltaX, deltaY);
    pthread_mutex_lock(&mutex);
    while (!moveEvents.empty()) {
        int storedDeltaX = moveEvents.front();
        moveEvents.pop();
        int storedDeltaY = moveEvents.front();
        moveEvents.pop();

        storedDeltaSumX += storedDeltaX;
        storedDeltaSumY += storedDeltaY;

        //NSLog(@"searching for %d %d: storedDeltaSumX: %d, storedDeltaSumY: %d",
        //      deltaX, deltaY, storedDeltaSumX, storedDeltaSumY);

        if (storedDeltaSumX == deltaX && storedDeltaSumY == deltaY) {
            //NSLog(@"Equal!");
            pthread_mutex_unlock(&mutex);
            return YES;
        } else {
            // either means that another app generated an event
            // or that mouse coalescing is enabled
            // UPDATE: Damn, we still have coalescing in normal use case. For example
            //         if we try to move a window. So I have to remove this log for now.
            //LOG(@"WARNING: Tampering detected or coalescing enabled (%d != %d, %d != %d)",
            //    deltaX, storedDeltaSumX, deltaY, storedDeltaSumY);
        }
    }

    //NSLog(@"no more");

    pthread_mutex_unlock(&mutex);

    return NO;
}

- (void) pushClickEvent {
    pthread_mutex_lock(&mutex);
    clickEvents++;
    pthread_mutex_unlock(&mutex);
}

- (void) popClickEvent {
    pthread_mutex_lock(&mutex);
    clickEvents--;
    pthread_mutex_unlock(&mutex);
}

- (int) numMoveEvents {
    int s;
    pthread_mutex_lock(&mutex);
    s = (int) moveEvents.size();
    pthread_mutex_unlock(&mutex);
    return s;
}

- (BOOL) hasClickEvents {
    int has;
    pthread_mutex_lock(&mutex);
    has = (clickEvents - clickEventsZeroLevel) > 0;
    pthread_mutex_unlock(&mutex);
    return has;
}

- (int) numClickEvents {
    int num;
    pthread_mutex_lock(&mutex);
    num = clickEvents;
    pthread_mutex_unlock(&mutex);
    return clickEvents;
}

- (void) resetClickEvents {
    pthread_mutex_lock(&mutex);
    clickEventsZeroLevel = clickEvents;
    pthread_mutex_unlock(&mutex);
}

@end
