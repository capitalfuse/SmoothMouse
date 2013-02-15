//
//  MouseSupervisor.m
//  SmoothMouse
//
//  Created by Daniel Åkerud on 2/4/13.
//
//

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
        [events insertObject:[NSNumber numberWithInt:deltaY] atIndex:0];
        [events insertObject:[NSNumber numberWithInt:deltaX] atIndex:0];
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

            [storedDeltaX release];
            [storedDeltaY release];

            if (storedDeltaSumX == deltaX && storedDeltaSumY == deltaY) {
                //NSLog(@"same");
                return YES;
            } else {
                //NSLog(@"NOT SAME, YET");
            }
        }
        //NSLog(@"DIDN'T FIND MATCH");
        return NO;
    }
}

- (int) numItems {
    return (int) [events count];
}

@end
