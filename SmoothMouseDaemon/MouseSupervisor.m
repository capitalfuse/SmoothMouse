
#import "MouseSupervisor.h"

#include <pthread.h>

@implementation MouseSupervisor

- (id)init
{
    self = [super init];
    if (self) {
        moveEvents = [[NSMutableArray alloc] initWithCapacity:5];
        clickEvents = 0;
        clickEventsZeroLevel = 0;
    }
    return self;
}

- (void) pushMoveEvent: (int) deltaX :(int) deltaY {
    @synchronized(self) {
        NSNumber *n1 = [NSNumber numberWithInt:deltaY];
        NSNumber *n2 = [NSNumber numberWithInt:deltaX];
        [moveEvents insertObject:n1 atIndex:0];
        [moveEvents insertObject:n2 atIndex:0];
        //NSLog(@"Pushed %d, %d", deltaX, deltaY);
    }
}

- (BOOL) popMoveEvent: (int) deltaX :(int)deltaY {
    int storedDeltaSumX = 0;
    int storedDeltaSumY = 0;
    //NSLog(@"searching for %d %d", deltaX, deltaY);
    @synchronized(self) {
        while ([moveEvents count] > 0) {
            NSNumber *storedDeltaY = [moveEvents lastObject];
            [moveEvents removeLastObject];
            NSNumber *storedDeltaX = [moveEvents lastObject];
            [moveEvents removeLastObject];

            storedDeltaSumX += [storedDeltaX intValue];
            storedDeltaSumY += [storedDeltaY intValue];

            //NSLog(@"searching for %d %d: storedDeltaSumX: %d, storedDeltaSumY: %d",
            //      deltaX, deltaY, storedDeltaSumX, storedDeltaSumY);

            if (storedDeltaSumX == deltaX && storedDeltaSumY == deltaY) {
                //NSLog(@"Equal!");
                return YES;
            } else {
                //NSLog(@"not equal %d != %d, %d != %d",
                //      deltaX, storedDeltaSumX, deltaY, storedDeltaSumY);
            }
        }
        //NSLog(@"no more");

        return NO;
    }
}

- (void) pushClickEvent {
    @synchronized(self) {
        clickEvents++;
    }
}

- (void) popClickEvent {
    @synchronized(self) {
        clickEvents--;
    }
}

- (int) numMoveEvents {
    @synchronized(self) {
        return (int) [moveEvents count];
    }
}

- (BOOL) hasClickEvents {
    @synchronized(self) {
        return (clickEvents - clickEventsZeroLevel) > 0;
    }
}

- (int) numClickEvents {
    @synchronized(self) {
        return clickEvents;
    }
}

- (void) resetClickEvents {
    @synchronized(self) {
        clickEventsZeroLevel = clickEvents;
    }
}

@end
