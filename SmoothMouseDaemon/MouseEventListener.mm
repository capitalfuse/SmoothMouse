
#import "MouseEventListener.h"
#import "debug.h"
#import "mach_timebase_util.h"
#import "MouseSupervisor.h"
#import "InterruptListener.h"
#import "DriverEventLog.h"
#import "Daemon.h"

//#include <CarbonEvents.h>

extern "C" {
    extern Boolean
    IsMouseCoalescingEnabled(void);

    extern OSStatus
    SetMouseCoalescingEnabled(
                              Boolean    inNewState,
                              Boolean *  outOldState);
}

const char *cg_event_type_to_string(CGEventType type) {
    switch (type) {
        case kCGEventMouseMoved: return "kCGEventMouseMoved";
        case kCGEventLeftMouseDragged: return "kCGEventLeftMouseDragged";
        case kCGEventRightMouseDragged: return "kCGEventRightMouseDragged";
        case kCGEventOtherMouseDragged: return "kCGEventOtherMouseDragged";
        default: return "?";
    }
}

@implementation MouseEventListener

CGEventRef
myCGEventCallback(CGEventTapProxy proxy, CGEventType type,
                  CGEventRef event, void *refcon)
{
    int64_t deltaX = CGEventGetIntegerValueField(event, kCGMouseEventDeltaX);
    int64_t deltaY = CGEventGetIntegerValueField(event, kCGMouseEventDeltaY);

    if ([[Config instance] latencyEnabled]) {
        static mach_timebase_info_data_t machTimebaseInfo;
        uint64_t timestampInterrupt = 0;
        uint64_t timestampNow = 0;
        uint64_t timestampKext = 0;

        if (machTimebaseInfo.denom == 0) {
            mach_timebase_info(&machTimebaseInfo);
        }

        BOOL ok;

        ok = [sInterruptListener get:&timestampInterrupt];

        if (!ok) {
            NSLog(@"No timestamp from interrupt (event injected?)");
            exit(1);
        }

        driver_event_t driverEvent;
        ok = [sDriverEventLog get:&driverEvent];

        if (!ok) {
            timestampKext = 0;
        } else {
            timestampKext = driverEvent.kextTimestamp;
        }

        timestampInterrupt = convert_from_mach_timebase_to_nanos(timestampInterrupt, &machTimebaseInfo);
        timestampKext = convert_from_mach_timebase_to_nanos(timestampKext, &machTimebaseInfo);
        timestampNow = convert_from_mach_timebase_to_nanos(mach_absolute_time(), &machTimebaseInfo);

        float latencyInterrupt = (timestampNow - timestampInterrupt) / 1000000.0;
        float latencyKext      = (timestampNow - timestampKext) / 1000000.0;

        LOG(@"Application received mouse event: %s (%d), dx: %d, dy: %d, lat int: %f ms, lat kext: %f ms, int events: %d",
            cg_event_type_to_string(type),
            type,
            (int)deltaX,
            (int)deltaY,
            (latencyInterrupt),
            (timestampKext == 0 ? 0 : latencyKext),
            [sInterruptListener numEvents]);
    }

    if (IsMouseCoalescingEnabled()) {
        LOG(@"ERROR: Mouse coalescing is enabled");
        exit(1);
    }

    if (type == kCGEventMouseMoved ||
        type == kCGEventLeftMouseDragged ||
        type == kCGEventRightMouseDragged ||
        type == kCGEventOtherMouseDragged) {

        //CGPoint location = CGEventGetLocation(event);

        BOOL match = [sMouseSupervisor popMoveEvent:(int) deltaX: (int) deltaY];
        if (!match) {
            mouse_refresh(REFRESH_REASON_POSITION_TAMPERING);
            if ([[Config instance] debugEnabled]) {
                if ([[Config instance] mouseEnabled] || [[Config instance] trackpadEnabled]) {
                    LOG(@"Mouse location tampering detected");
                }
            }
        } else {
            //NSLog(@"MATCH: %d, queue size: %d, delta x: %f, delta y: %f",
            //      match,
            //      [sMouseSupervisor numItems],
            //      [event deltaX],
            //      [event deltaY]
            //      );
        }
    } else if (type == kCGEventLeftMouseDown) {
        //LOG(@"LEFT MOUSE CLICK (ClickCount: %ld)", (long)[event clickCount]);
        if ([[Config instance] debugEnabled]) {
            [sMouseSupervisor popClickEvent];
            if ([sMouseSupervisor hasClickEvents]) {
                LOG(@"WARNING: click event probably lost");
                if ([[Config instance] sayEnabled]) {
                    [[Daemon instance] say:@"There was one lost mouse click"];
                }
                [sMouseSupervisor resetClickEvents];
            }
        }
    } else if (type == NSLeftMouseDown) {
        //LOG(@"LEFT MOUSE RELEASE");
    }

    return event;
}

static void *MouseEventListenerThread(void *instance)
{
    //LOG(@"MouseEventListenerThread: Start");

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    SetMouseCoalescingEnabled(false, NULL);

    MouseEventListener *self = (MouseEventListener *) instance;

    CFMachPortRef      eventTap;
    CGEventMask        eventMask;
    CFRunLoopSourceRef runLoopSource;

    // Create an event tap. We are interested in mouse movements.
    eventMask  = 0;
    eventMask |= CGEventMaskBit(kCGEventMouseMoved);
    eventMask |= CGEventMaskBit(kCGEventLeftMouseDragged);
    eventMask |= CGEventMaskBit(kCGEventRightMouseDragged);
    eventMask |= CGEventMaskBit(kCGEventOtherMouseDragged);
    eventMask |= CGEventMaskBit(kCGEventLeftMouseDown);
    eventMask |= CGEventMaskBit(kCGEventLeftMouseUp);
    eventMask |= CGEventMaskBit(kCGEventRightMouseDown);
    eventMask |= CGEventMaskBit(kCGEventRightMouseUp);
    eventMask |= CGEventMaskBit(kCGEventOtherMouseDown);
    eventMask |= CGEventMaskBit(kCGEventOtherMouseUp);

    eventTap = CGEventTapCreate(
                                kCGSessionEventTap, kCGHeadInsertEventTap,
                                0, eventMask, myCGEventCallback, NULL);
    if (!eventTap) {
        fprintf(stderr, "failed to create event tap\n");
        exit(1);
    }

    // Create a run loop source.
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);

    // Add to the current run loop.
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);

    // Enable the event tap.
    CGEventTapEnable(eventTap, true);

    self->runLoop = [NSRunLoop currentRunLoop];

    NSDate *date = [NSDate distantFuture];

    while (self->running && [self->runLoop runMode:NSDefaultRunLoopMode beforeDate:date]);

    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);

    CGEventTapEnable(eventTap, false);

    CFRelease(eventTap);

    CFRelease(runLoopSource);

    [pool drain];

    //LOG(@"MouseEventListenerThread: End");

    return NULL;
}

-(void) start {
    //LOG(@"MouseEventListener::start");
    running = 1;
    int err = pthread_create(&threadId, NULL, &MouseEventListenerThread, self);
    if (err != 0) {
        NSLog(@"Failed to start MouseEventListenerThread");
        running = 0;
    }
}

-(void) stop {
    //LOG(@"MouseEventListener::stop");
    running = 0;

    [runLoop performSelector: @selector(stopThread:) target:self argument:nil order:0 modes:[NSArray arrayWithObject:NSDefaultRunLoopMode]];

    // need to wake up after posting a selector to the runloop:
    // http://www.cocoabuilder.com/archive/cocoa/228634-nsrunloop-performselector-needs-cfrunloopwakeup.html
    CFRunLoopRef crf = [runLoop getCFRunLoop];
    CFRunLoopWakeUp(crf);

    int rv = pthread_join(threadId, NULL);
    if (rv != 0) {
        NSLog(@"Failed to wait for MouseEventListenerThread");
    }

}

-(void) stopThread: (id) argument {
    //LOG(@"MouseEventListener::stopThread");
    CFRunLoopStop([[NSRunLoop currentRunLoop] getCFRunLoop]);
}
@end
