
#import "MouseSupervisor.h"

#include <pthread.h>

@implementation MouseSupervisor

- (id)init
{
    self = [super init];
    if (self) {
        events = [[NSMutableArray alloc] initWithCapacity:5];
    }
    return self;
}

- (void) pushMouseEvent: (int) deltaX :(int) deltaY {
    @synchronized(self) {
        NSNumber *n1 = [NSNumber numberWithInt:deltaY];
        NSNumber *n2 = [NSNumber numberWithInt:deltaX];
        [events insertObject:n1 atIndex:0];
        [events insertObject:n2 atIndex:0];
    }
}

- (BOOL) popMouseEvent: (int) deltaX :(int)deltaY {
    int storedDeltaSumX = 0;
    int storedDeltaSumY = 0;
    @synchronized(self) {
        while ([events count] > 0) {
            NSNumber *storedDeltaY = [events lastObject];
            [events removeLastObject];
            NSNumber *storedDeltaX = [events lastObject];
            [events removeLastObject];

            storedDeltaSumX += [storedDeltaX intValue];
            storedDeltaSumY += [storedDeltaY intValue];

            if (storedDeltaSumX == deltaX && storedDeltaSumY == deltaY) {
                return YES;
            }
        }
        return NO;
    }
}

- (int) numItems {
    return (int) [events count];
}

@end
