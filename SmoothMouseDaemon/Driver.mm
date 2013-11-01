
#include "mouse.h"
#include "debug.h"
#include <sys/time.h>
#include <pthread.h>
#include <IOKit/hidsystem/event_status_driver.h>
#include <IOKit/hidsystem/IOHIDShared.h>

#import "Daemon.h"
#import "DriverEventLog.h"

#include <list>

#include "prio.h"
#include "driver.h"
#include "debug.h"

int numCoalescedEvents;

static CGEventSourceRef eventSource = NULL;
static io_connect_t iohid_connect = MACH_PORT_NULL;
static pthread_t driverEventThreadID;

static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t data_available = PTHREAD_COND_INITIALIZER;

static std::list<driver_event_t> event_queue;
static BOOL keep_running;

static void *DriverEventThread(void *instance);
static BOOL driver_handle_button_event(driver_button_event_t *event);
static BOOL driver_handle_move_event(driver_move_event_t *event);

BOOL is_move_event(driver_event_t *event) {
    return (event->id == DRIVER_EVENT_ID_MOVE);
}

BOOL can_coalesce(driver_move_event_t *e1, driver_move_event_t *e2)
{
    if (e1->type == e2->type &&
        e1->buttons == e2->buttons &&
        e1->otherButton == e2->otherButton) {
        return YES;
    } else {
        if ([[Config instance] debugEnabled]) {
            LOG(@"Can't Coalesce, t1: %d, t2: %d, b1: %d, b2: %d, ob1: %d, ob2: %d",
                e1->type,
                e2->type,
                e1->buttons,
                e2->buttons,
                e1->otherButton,
                e2->otherButton);
        }
        return NO;
    }
}

BOOL driver_post_event(driver_event_t *event) {
    pthread_mutex_lock(&mutex);
    if (!event_queue.empty() && is_move_event(event)) {
        driver_event_t back = event_queue.back();
        if (can_coalesce(&event->move, &(back.move))) {
            event_queue.pop_back();
            event->move.deltaX += back.move.deltaX;
            event->move.deltaY += back.move.deltaY;
            ++numCoalescedEvents;
        }
    }
    event_queue.push_back(*event);
    pthread_cond_signal(&data_available);
    pthread_mutex_unlock(&mutex);
    return YES;
}

const char *driver_quartz_event_type_to_string(CGEventType type) {
    switch(type) {
        case kCGEventNull:              return "kCGEventNull";
        case kCGEventLeftMouseUp:       return "kCGEventLeftMouseUp";
        case kCGEventLeftMouseDown:     return "kCGEventLeftMouseDown";
        case kCGEventLeftMouseDragged:  return "kCGEventLeftMouseDragged";
        case kCGEventRightMouseUp:      return "kCGEventRightMouseUp";
        case kCGEventRightMouseDown:    return "kCGEventRightMouseDown";
        case kCGEventRightMouseDragged: return "kCGEventRightMouseDragged";
        case kCGEventOtherMouseUp:      return "kCGEventOtherMouseUp";
        case kCGEventOtherMouseDown:    return "kCGEventOtherMouseDown";
        case kCGEventOtherMouseDragged: return "kCGEventOtherMouseDragged";
        case kCGEventMouseMoved:        return "kCGEventMouseMoved";
        default:                        return "?";
    }
}

const char *driver_iohid_event_type_to_string(int type) {
    switch(type) {
        case NX_NULLEVENT:      return "NX_NULLEVENT";
        case NX_LMOUSEUP:       return "NX_LMOUSEUP";
        case NX_LMOUSEDOWN:     return "NX_LMOUSEDOWN";
        case NX_LMOUSEDRAGGED:  return "NX_LMOUSEDRAGGED";
        case NX_RMOUSEUP:       return "NX_RMOUSEUP";
        case NX_RMOUSEDOWN:     return "NX_RMOUSEDOWN";
        case NX_RMOUSEDRAGGED:  return "NX_RMOUSEDRAGGED";
        case NX_OMOUSEUP:       return "NX_OMOUSEUP";
        case NX_OMOUSEDOWN:     return "NX_OMOUSEDOWN";
        case NX_OMOUSEDRAGGED:  return "NX_OMOUSEDRAGGED";
        case NX_MOUSEMOVED:     return "NX_MOUSEMOVED";
        default:                return "?";
    }
}

static void *DriverEventThread(void *instance)
{
    //LOG(@"DriverEventThread: Start");

    [Prio setRealtimePrio: @"DriverEventThread" withComputation:200000 withConstraint:300000];

    while(keep_running) {
        driver_event_t event;
        pthread_mutex_lock(&mutex);
        while(event_queue.empty()) {
            pthread_cond_wait(&data_available, &mutex);
        }
        double start = GET_TIME();
        event = event_queue.front();
        event_queue.pop_front();
        pthread_mutex_unlock(&mutex);

        if ([[Config instance] latencyEnabled]) {
            [sDriverEventLog add:&event];
        }

        switch(event.id) {
            case DRIVER_EVENT_ID_MOVE:
                //LOG(@"DRIVER_EVENT_ID_MOVE");
                driver_handle_move_event((driver_move_event_t *)&(event.move));
                break;
            case DRIVER_EVENT_ID_BUTTON:
                //LOG(@"DRIVER_EVENT_ID_BUTTON");
                driver_handle_button_event((driver_button_event_t *)&(event.button));
                break;
            case DRIVER_EVENT_ID_TERMINATE:
                //LOG(@"DRIVER_EVENT_ID_TERMINATE");
                break;
            default:
                //LOG(@"UNKNOWN DRIVER EVENT (%d)", event.id);
                break;
        }
        double end = GET_TIME();
        if ([[Config instance] timingsEnabled]) {
            LOG(@"driver timings: total time time in mach time units: %f", (end-start));
        }

    }

    //NSLog(@"DriverEventThread: End");

    return NULL;
}

BOOL driver_init() {
    numCoalescedEvents = 0;

    switch ([[Config instance] driver]) {
        case DRIVER_QUARTZ_OLD:
        {
            if (CGSetLocalEventsFilterDuringSuppressionState(kCGEventFilterMaskPermitAllEvents,
                                                             kCGEventSuppressionStateRemoteMouseDrag)) {
                NSLog(@"call to CGSetLocalEventsFilterDuringSuppressionState failed");
                /* whatever, but don't continue with interval */
                break;
            }

            if (CGSetLocalEventsSuppressionInterval(0.0)) {
                NSLog(@"call to CGSetLocalEventsSuppressionInterval failed");
                /* ignore */
            }
            break;
        }
        case DRIVER_QUARTZ:
        {
            eventSource = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
            if (eventSource == NULL) {
                NSLog(@"call to CGEventSourceSetKeyboardType failed");
                return NO;
            }
            break;
        }
        case DRIVER_IOHID:
        {
            io_connect_t service_connect = IO_OBJECT_NULL;
            io_service_t service;

            service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching(kIOHIDSystemClass));
            if (!service) {
                NSLog(@"call to IOServiceGetMatchingService failed");
                return NO;
            }

            kern_return_t kern_ret = IOServiceOpen(service, mach_task_self(), kIOHIDParamConnectType, &service_connect);
            if (kern_ret != KERN_SUCCESS) {
                NSLog(@"call to IOServiceOpen failed");
                return NO;
            }

            IOObjectRelease(service);

            iohid_connect = service_connect;
            
            break;
        }
    }

    keep_running = YES;

    int threadError = pthread_create(&driverEventThreadID, NULL, &DriverEventThread, NULL);
    if (threadError != 0)
    {
        NSLog(@"Failed to start driver event thread");
        return NO;
    }

    return YES;
}

BOOL driver_cleanup() {

    keep_running = NO;

    driver_event_t terminate_event;
    terminate_event.id = DRIVER_EVENT_ID_TERMINATE;
    driver_post_event(&terminate_event);

    int rv = pthread_join(driverEventThreadID, NULL);
    if (rv != 0) {
        NSLog(@"Failed to wait for driver event thread");
    }

    switch ([[Config instance] driver]) {
        case DRIVER_QUARTZ_OLD:
            break;
        case DRIVER_QUARTZ:
        {
            CFRelease(eventSource);
            eventSource = NULL;
            break;
        }
        case DRIVER_IOHID:
        {
            if (iohid_connect != MACH_PORT_NULL) {
                (void) IOServiceClose(iohid_connect);
            }
            iohid_connect = MACH_PORT_NULL;
            break;
        }
    }

    return YES;
}

BOOL driver_handle_move_event(driver_move_event_t *event) {
    int driver_to_use = [[Config instance] driver];

    // NOTE: can't get middle mouse to work in iohid, so let's channel all "other" events
    //       through quartz
    if (driver_to_use == DRIVER_IOHID && event->type == kCGEventOtherMouseDragged) {
        driver_to_use = DRIVER_QUARTZ;
    }

    const char *driverString = driver_get_driver_string(driver_to_use);

    if ([[Daemon instance] isMouseEventListenerActive]) {
        [sMouseSupervisor pushMoveEvent: event->deltaX: event->deltaY];
    }

    e1 = GET_TIME();
    switch (driver_to_use) {
        case DRIVER_QUARTZ_OLD:
        {
            if (kCGErrorSuccess != CGPostMouseEvent(event->pos, true, 1, BUTTON_DOWN(event->buttons, LEFT_BUTTON))) {
                NSLog(@"Failed to post mouse event");
                exit(0);
            }

            e2 = GET_TIME();

            if ([[Config instance] debugEnabled]) {
                LOG(@"%s:MOVE: pos.x: %d, pos.y: %d, time: %f",
                    driverString,
                    (int)event->pos.x,
                    (int)event->pos.y,
                    (e2-e1));
            }
            break;
        }
        case DRIVER_QUARTZ:
        {
            CGEventRef evt = CGEventCreateMouseEvent(eventSource, event->type, event->pos, event->otherButton);
            CGEventSetIntegerValueField(evt, kCGMouseEventDeltaX, event->deltaX);
            CGEventSetIntegerValueField(evt, kCGMouseEventDeltaY, event->deltaY);
            CGEventPost(kCGSessionEventTap, evt);
            CFRelease(evt);

            e2 = GET_TIME();

            if ([[Config instance] debugEnabled]) {
                LOG(@"%s:MOVE: eventType: %s(%d), pos.x: %d, pos.y: %d, dx: %d, dy: %d, time: %f",
                    driverString,
                    driver_quartz_event_type_to_string(event->type),
                    (int)event->type,
                    (int)event->pos.x,
                    (int)event->pos.y,
                    (int)event->deltaX,
                    (int)event->deltaY,
                    (e2-e1));
            }
            break;
        }
        case DRIVER_IOHID:
        {
            int iohidEventType;

            switch (event->type) {
                case kCGEventMouseMoved:
                    iohidEventType = NX_MOUSEMOVED;
                    break;
                case kCGEventLeftMouseDragged:
                    iohidEventType = NX_LMOUSEDRAGGED;
                    break;
                case kCGEventRightMouseDragged:
                    iohidEventType = NX_RMOUSEDRAGGED;
                    break;
                case kCGEventOtherMouseDragged:
                    iohidEventType = NX_OMOUSEDRAGGED;
                    break;
                default:
                    NSLog(@"INTERNAL ERROR: unknown eventType: %d", event->type);
                    exit(0);
            }

            NXEventData eventData;

            IOGPoint newPoint = { (SInt16) event->pos.x, (SInt16) event->pos.y};

            bzero(&eventData, sizeof(NXEventData));
            eventData.mouseMove.dx = (SInt32)(event->deltaX);
            eventData.mouseMove.dy = (SInt32)(event->deltaY);

            IOOptionBits options;
            if (iohidEventType == NX_MOUSEMOVED) {
                options = kIOHIDSetRelativeCursorPosition;
                // NOTE: newPoint has no effect in relative mode, you can set it to {0, 0}
                //       without any issues.
            } else {
                options = kIOHIDSetCursorPosition;
            }

            (void)IOHIDPostEvent(iohid_connect,
                                 iohidEventType,
                                 newPoint,
                                 &eventData,
                                 kNXEventDataVersion,
                                 0,
                                 options);

            e2 = GET_TIME();

            if ([[Config instance] debugEnabled]) {
                LOG(@"%s:MOVE: eventType: %s(%d), newPoint.x: %d, newPoint.y: %d, dx: %d, dy: %d, time: %f",
                    driverString,
                    driver_iohid_event_type_to_string(iohidEventType),
                    (int)iohidEventType,
                    (int)newPoint.x,
                    (int)newPoint.y,
                    (int)eventData.mouseMove.dx,
                    (int)eventData.mouseMove.dy,
                    (e2-e1));
            }

            break;
        }
        default:
        {
            NSLog(@"Driver %d not implemented: ", driver_to_use);
            exit(0);
        }
    }

    e2 = GET_TIME();

    return YES;
}

BOOL driver_handle_button_event(driver_button_event_t *event) {
    int driver_to_use = [[Config instance] driver];

    // NOTE: can't get middle mouse to work in iohid, so let's channel all "other" events
    //       through quartz
    if (driver_to_use == DRIVER_IOHID &&
        (event->type == kCGEventOtherMouseDown || event->type == kCGEventOtherMouseUp)) {
        driver_to_use = DRIVER_QUARTZ;
    }

    const char *driverString = driver_get_driver_string(driver_to_use);

    int clickStateValue;
    switch(event->type) {
        case kCGEventLeftMouseDown:
        case kCGEventLeftMouseUp:
            clickStateValue = event->nclicks;
            break;
        case kCGEventRightMouseDown:
        case kCGEventOtherMouseDown:
        case kCGEventRightMouseUp:
        case kCGEventOtherMouseUp:
            clickStateValue = 1;
            break;
        default:
            NSLog(@"INTERNAL ERROR: illegal eventType: %d", event->type);
            exit(0);
    }

    if (event->type == kCGEventLeftMouseDown) {
        [sMouseSupervisor pushClickEvent];
    }

    e1 = GET_TIME();
    switch (driver_to_use) {
        case DRIVER_QUARTZ_OLD:
        {
            if (kCGErrorSuccess != CGPostMouseEvent(event->pos, true, 1, BUTTON_DOWN(event->buttons, LEFT_BUTTON))) {
                NSLog(@"Failed to post mouse event");
                exit(0);
            }

            e2 = GET_TIME();

            if ([[Config instance] debugEnabled]) {
                LOG(@"%s:BUTTON: pos.x: %d, pos.y: %d, time: %f",
                    driverString,
                    (int)event->pos.x,
                    (int)event->pos.y,
                    (e2-e1));
            }

            break;
        }
        case DRIVER_QUARTZ:
        {
            CGEventRef evt = CGEventCreateMouseEvent(eventSource, event->type, event->pos, event->otherButton);
            CGEventSetIntegerValueField(evt, kCGMouseEventClickState, clickStateValue);
            CGEventPost(kCGSessionEventTap, evt);
            CFRelease(evt);

            e2 = GET_TIME();

            if ([[Config instance] debugEnabled]) {
                LOG(@"%s:BUTTON: eventType: %s(%d), pos: %dx%d, csv: %d, time: %f",
                    driverString,
                    driver_quartz_event_type_to_string(event->type),
                    (int)event->type,
                    (int)event->pos.x,
                    (int)event->pos.y,
                    clickStateValue,
                    (e2-e1));
            }
            break;
        }
        case DRIVER_IOHID:
        {
            int iohidEventType;
            int is_down_event = 1;

            switch(event->type) {
                case kCGEventLeftMouseDown:
                    iohidEventType = NX_LMOUSEDOWN;
                    break;
                case kCGEventLeftMouseUp:
                    iohidEventType = NX_LMOUSEUP;
                    is_down_event = 0;
                    break;
                case kCGEventRightMouseDown:
                    iohidEventType = NX_RMOUSEDOWN;
                    break;
                case kCGEventRightMouseUp:
                    iohidEventType = NX_RMOUSEUP;
                    is_down_event = 0;
                    break;
                case kCGEventOtherMouseDown:
                    iohidEventType = NX_OMOUSEDOWN;
                    break;
                case kCGEventOtherMouseUp:
                    iohidEventType = NX_OMOUSEUP;
                    is_down_event = 0;
                    break;
                default:
                    NSLog(@"INTERNAL ERROR: unknown eventType: %d", event->type);
                    exit(0);
            }

            IOGPoint newPoint = { (SInt16) event->pos.x, (SInt16) event->pos.y };

            NXEventData eventData;
            kern_return_t result;

            if ([[Config instance] debugEnabled]) {
                LOG(@"%s:BUTTON: Sending AUX mouse button event", driverString);
            }
            bzero(&eventData, sizeof(NXEventData));
            eventData.compound.misc.L[0] = 1;
            eventData.compound.misc.L[1] = is_down_event;
            eventData.compound.subType = NX_SUBTYPE_AUX_MOUSE_BUTTONS;

            result = IOHIDPostEvent(iohid_connect, NX_SYSDEFINED, newPoint, &eventData, kNXEventDataVersion, 0, 0);

            if (result != KERN_SUCCESS) {
                NSLog(@"failed to post aux button event");
            }

            static int eventNumber = 0;
            if (is_down_event) eventNumber++;

            UInt8 subType = NX_SUBTYPE_DEFAULT;
            if ([[Config instance ] activeAppRequiresTabletPointSubtype]) {
                if ([[Config instance] debugEnabled]) {
                    LOG(@"Setting subType to TABLET_POINT");
                }
                subType = NX_SUBTYPE_TABLET_POINT;
            }

            bzero(&eventData, sizeof(NXEventData));
            eventData.mouse.click = is_down_event ? clickStateValue : 0;
            eventData.mouse.pressure = is_down_event ? 255 : 0;
            eventData.mouse.eventNum = eventNumber;
            eventData.mouse.buttonNumber = event->otherButton;
            eventData.mouse.subType = subType;

            result = IOHIDPostEvent(iohid_connect,
                                    iohidEventType,
                                    newPoint,
                                    &eventData,
                                    kNXEventDataVersion,
                                    0,
                                    0);

            if (result != KERN_SUCCESS) {
                NSLog(@"failed to post button event");
            }

            e2 = GET_TIME();

            if ([[Config instance] debugEnabled]) {
                LOG(@"%s:BUTTON: eventType: %s(%d), pos: %dx%d, subt: %d, click: %d, pressure: %d, eventNumber: %d, buttonNumber: %d, time: %f",
                    driverString,
                    driver_iohid_event_type_to_string(iohidEventType),
                    (int)iohidEventType,
                    (int)newPoint.x,
                    (int)newPoint.y,
                    (int)eventData.mouse.subType,
                    (int)eventData.mouse.click,
                    (int)eventData.mouse.pressure,
                    (int)eventData.mouse.eventNum,
                    (int)eventData.mouse.buttonNumber,
                    (e2-e1));
            }

            break;
        }
        default:
        {
            NSLog(@"Driver %d not implemented: ", driver_to_use);
            exit(0);
        }
    }

    e2 = GET_TIME();

    return YES;
}

const char *driver_get_driver_string(int driver) {
    switch (driver) {
        case DRIVER_QUARTZ_OLD: return "QUARTZ_OLD";
        case DRIVER_QUARTZ: return "QUARTZ";
        case DRIVER_IOHID: return "IOHID";
        default: return "?";
    }
}

