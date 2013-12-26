//
//  AppDelegate.m
//  InputMeasurement
//
//  Created by Daniel Åkerud on 6/23/13.
//  Copyright (c) 2013 -. All rights reserved.
//

#import "AppDelegate.h"

#include <mach/mach_time.h>

#define FILTER (0.95)

uint64_t convert_from_mach_timebase_to_nanos(uint64_t mach_time, mach_timebase_info_data_t *info)
{
    double timebase = (double)(info->numer) / (double)(info->denom);
    uint64_t nanos = mach_time * timebase;
    //NSLog(@"convert_from_mach_timebase_to_nanos: %llu => %llu", mach_time, nanos);
    return nanos;
}

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSLog(@"applicationDidFinishLaunching");
    [self hookEvents];
}

-(BOOL) hookEvents
{
    eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:(NSKeyDownMask | NSLeftMouseDownMask | NSKeyUpMask | NSLeftMouseUpMask) handler:^(NSEvent *event){
        [self handleEvent:event];
        return event;
    }];

    NSLog(@"Registered event monitor");

    return YES;
}

-(BOOL) unhookEvents
{
    if (eventMonitor != NULL) {
        [NSEvent removeMonitor:eventMonitor];
        eventMonitor = NULL;
    }

    NSLog(@"Removed event monitor");

    return YES;
}

-(NSString *) eventToString: (NSEventType) type {
    switch (type) {
        case NSLeftMouseDown:
            return @"NSLeftMouseDown";
        case NSLeftMouseUp:
            return @"NSLeftMouseUp";
        case NSKeyDown:
            return @"NSKeyDown";
        case NSKeyUp:
            return @"NSKeyUp";
        default:
            return @"?";
    }
}

-(void) handleEvent:(NSEvent *) event
{
    NSLog(@"yo");
    NSEventType type = [event type];
    mach_timebase_info_data_t info;
    kern_return_t kret = mach_timebase_info(&info);
    if (kret != KERN_SUCCESS) {
        NSLog(@"call to mach_timebase_info failed: %d", kret);
    }

    uint64_t nowMach = mach_absolute_time();

    double nowMs = convert_from_mach_timebase_to_nanos(nowMach, &info) / 1000000.0;

    if (type == NSLeftMouseDown) {
        timeMouseMs = nowMs;
    } else if (type == NSKeyDown) {
        timeKeyMs = nowMs;
    } else if (type == NSKeyUp || type == NSLeftMouseUp) {
        timeKeyMs = timeMouseMs = 0;
    }

    if (timeMouseMs != 0 && timeKeyMs != 0) {
        double diffMs = timeKeyMs - timeMouseMs;
        NSLog(@"Mouse-Key time diff: %f ms", diffMs);
        if (averageMs == 0) {
            averageMs = diffMs;
        } else {
            averageMs = averageMs * FILTER + diffMs * (1 - FILTER);
        }
        [_label setStringValue:[NSString stringWithFormat:@"Keyboard was %f ms after mouse", averageMs]];
    }
}

@end
