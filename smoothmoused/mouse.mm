
#include "mouse.h"
#include "debug.h"

#include <sys/time.h>
#include <IOKit/hidsystem/event_status_driver.h>
#include <IOKit/hidsystem/IOHIDShared.h>

#include "WindowsFunction.hpp"
#include "OSXFunction.hpp"

#define LEFT_BUTTON     4
#define RIGHT_BUTTON    1
#define MIDDLE_BUTTON   2
#define BUTTON4         8
#define BUTTON5         16
#define BUTTON6         32
#define NUM_BUTTONS     6

#define BUTTON_DOWN(curbuttons, button)                         (((button) & curbuttons) == (button))
#define BUTTON_UP(curbuttons, button)                           (((button) & curbuttons) == 0)
#define BUTTON_STATE_CHANGED(curbuttons, lastbuttons, button)   ((lastButtons & (button)) != (curbuttons & (button)))

WindowsFunction *win = NULL;
OSXFunction *osx_mouse = NULL;
OSXFunction *osx_trackpad = NULL;

io_connect_t iohid_connect = MACH_PORT_NULL;

extern BOOL is_debug;

extern double velocity_mouse;
extern double velocity_trackpad;
extern AccelerationCurve curve_mouse;
extern AccelerationCurve curve_trackpad;
extern Driver driver;

static CGEventSourceRef eventSource = NULL;
static CGPoint deltaPosInt;
static CGPoint deltaPosFloat;
static CGPoint currentPos;
static CGPoint lastPos;
static int lastButtons = 0;
static int nclicks = 0;
static CGPoint lastClickPos;
static double lastClickTime = 0;
static double doubleClickSpeed;
static uint64_t lastSequenceNumber = 0;

static pthread_mutex_t clickCountMutex = PTHREAD_MUTEX_INITIALIZER;

static double timestamp()
{
	struct timeval t;
	gettimeofday(&t, NULL);
	return (double)t.tv_sec + 1.0e-6 * (double)t.tv_usec;
}

static double get_distance(CGPoint pos0, CGPoint pos1) {
    CGFloat deltaX = pos1.x - pos0.x;
    CGFloat deltaY = pos1.y - pos0.y;
    CGFloat distance = sqrt(deltaX * deltaX + deltaY * deltaY);
    return distance;
}

static const char *event_type_to_string(CGEventType type) {
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

static CGPoint restrict_to_screen_boundaries(CGPoint lastPos, CGPoint newPos) {
    /*
	 The following code checks if cursor is in screen borders. It was ported
	 from Synergy.
	 */
    CGPoint pos = newPos;
    CGDisplayCount displayCount = 0;
	CGGetDisplaysWithPoint(newPos, 0, NULL, &displayCount);
	if (displayCount == 0) {
		displayCount = 0;
		CGDirectDisplayID displayID;
		CGGetDisplaysWithPoint(lastPos, 1,
							   &displayID, &displayCount);
		if (displayCount != 0) {
			CGRect displayRect = CGDisplayBounds(displayID);
			if (pos.x < displayRect.origin.x) {
				pos.x = displayRect.origin.x;
			}
			else if (pos.x > displayRect.origin.x +
					 displayRect.size.width - 1) {
				pos.x = displayRect.origin.x + displayRect.size.width - 1;
			}
			if (pos.y < displayRect.origin.y) {
				pos.y = displayRect.origin.y;
			}
			else if (pos.y > displayRect.origin.y +
					 displayRect.size.height - 1) {
				pos.y = displayRect.origin.y + displayRect.size.height - 1;
			}
		}
	}
    return pos;
}

static CGPoint get_current_mouse_pos() {
    CGEventRef event = CGEventCreate(NULL);
    CGPoint currentPos = CGEventGetLocation(event);
    CFRelease(event);
    //NSLog(@"got cursor position: %f,%f", currentPos.x, currentPos.y);
    return currentPos;
}

void mouse_update_clicktime() {
    pthread_mutex_lock(&clickCountMutex);
    NXEventHandle handle = NXOpenEventStatus();
	doubleClickSpeed = NXClickTime(handle);
    NXCloseEventStatus(handle);
    pthread_mutex_unlock(&clickCountMutex);
    //NSLog(@"clicktime updated: %f", clickTime);
}

bool mouse_init() {
    mouse_update_clicktime();

    currentPos = deltaPosFloat = deltaPosInt = get_current_mouse_pos();

    switch (driver) {
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
            mach_port_t io_master_port = MACH_PORT_NULL;

            kern_return_t kern_ret = IOMasterPort(MACH_PORT_NULL, &io_master_port);
            if (kern_ret != KERN_SUCCESS) {
                NSLog(@"call to IOMasterPort failed");
                return NO;
            }

            if (io_master_port == MACH_PORT_NULL) {
                NSLog(@"failed to get io master port");
                return NO;
            }

            service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching(kIOHIDSystemClass));
            if (!service) {
                NSLog(@"call to IOServiceGetMatchingService failed");
                return NO;
            }

            kern_ret = IOServiceOpen(service, mach_task_self(), kIOHIDParamConnectType, &service_connect);
            if (kern_ret != KERN_SUCCESS) {
                NSLog(@"call to IOServiceOpen failed");
                return NO;
            }

            IOObjectRelease(service);

            iohid_connect = service_connect;

            break;
        }
    }

	return YES;
}

void mouse_cleanup() {
    if (win != NULL) {
        delete win;
        win = NULL;
    }

    switch (driver) {
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
}

static void mouse_handle_move(int deviceType, int dx, int dy, double velocity, AccelerationCurve curve, int currentButtons) {
    CGPoint newPos;

    float calcdx;
    float calcdy;

    if (curve == ACCELERATION_CURVE_WINDOWS) {
        // map slider to [-5 <=> +5]
        int slider = (int)((velocity * 4) - 6);
        if (slider > 5) {
            slider = 5;
        }
        if (win == NULL) {
            win = new WindowsFunction(slider);
        }
        if (win->slider != slider) {
            delete win;
            win = new WindowsFunction(slider);
        }
        int newdx;
        int newdy;
        win->apply(dx, dy, &newdx, &newdy);
        calcdx = (float) newdx;
        calcdy = (float) newdy;
    } else if (curve == ACCELERATION_CURVE_OSX) {
        float speed = velocity;
        if (deviceType == kDeviceTypeTrackpad && osx_trackpad == NULL) {
            osx_trackpad = new OSXFunction("touchpad", speed);
        } else if (deviceType == kDeviceTypeMouse && osx_mouse == NULL) {
            osx_mouse = new OSXFunction("mouse", speed);
        }
        int newdx;
        int newdy;
        OSXFunction *osx = NULL;
        switch (deviceType) {
            case kDeviceTypeTrackpad:
                osx = osx_trackpad;
                break;
            case kDeviceTypeMouse:
                osx = osx_mouse;
                break;
            default:
                NSLog(@"invalid deviceType: %d", deviceType);
                exit(0);
        }
        osx->apply(dx, dy, &newdx, &newdy);
        calcdx = (float) newdx;
        calcdy = (float) newdy;
    }
    else {
        calcdx = (velocity * dx);
        calcdy = (velocity * dy);
    }

    newPos.x = currentPos.x + calcdx;
    newPos.y = currentPos.y + calcdy;

    newPos = restrict_to_screen_boundaries(currentPos, newPos);

    CGEventType eventType = kCGEventMouseMoved;
    CGMouseButton otherButton = 0;

    if (BUTTON_DOWN(currentButtons, LEFT_BUTTON)) {
        eventType = kCGEventLeftMouseDragged;
        otherButton = kCGMouseButtonLeft;
    } else if (BUTTON_DOWN(currentButtons, RIGHT_BUTTON)) {
        eventType = kCGEventRightMouseDragged;
        otherButton = kCGMouseButtonRight;
    } else if (BUTTON_DOWN(currentButtons, MIDDLE_BUTTON)) {
        eventType = kCGEventOtherMouseDragged;
        otherButton = kCGMouseButtonCenter;
    } else if (BUTTON_DOWN(currentButtons, BUTTON4)) {
        eventType = kCGEventOtherMouseDragged;
        otherButton = 3;
    } else if (BUTTON_DOWN(currentButtons, BUTTON5)) {
        eventType = kCGEventOtherMouseDragged;
        otherButton = 4;
    } else if (BUTTON_DOWN(currentButtons, BUTTON6)) {
        eventType = kCGEventOtherMouseDragged;
        otherButton = 5;
    }

    deltaPosFloat.x += calcdx;
    deltaPosFloat.y += calcdy;
    int deltaX = (int) (deltaPosFloat.x - deltaPosInt.x);
    int deltaY = (int) (deltaPosFloat.y - deltaPosInt.y);
    deltaPosInt.x += deltaX;
    deltaPosInt.y += deltaY;

    if (is_debug) {
        LOG(@"move dx: %d, dy: %d, cur: %.2fx%.2f, delta: %.2fx%.2f, buttons(LMR456): %d%d%d%d%d%d, eventType: %s(%d), otherButton: %d",
            dx,
            dy,
            currentPos.x,
            currentPos.y,
            deltaPosInt.x,
            deltaPosInt.y,
            BUTTON_DOWN(currentButtons, LEFT_BUTTON),
            BUTTON_DOWN(currentButtons, MIDDLE_BUTTON),
            BUTTON_DOWN(currentButtons, RIGHT_BUTTON),
            BUTTON_DOWN(currentButtons, BUTTON4),
            BUTTON_DOWN(currentButtons, BUTTON5),
            BUTTON_DOWN(currentButtons, BUTTON6),
            event_type_to_string(eventType),
            eventType,
            otherButton);
    }

    int driver_to_use = driver;

    if (driver == DRIVER_IOHID && eventType == kCGEventOtherMouseDragged) {
        driver_to_use = DRIVER_QUARTZ;
    }

    e1 = GET_TIME();
    switch (driver_to_use) {
        case DRIVER_QUARTZ_OLD:
        {
            if (kCGErrorSuccess != CGPostMouseEvent(newPos, true, 1, BUTTON_DOWN(currentButtons, LEFT_BUTTON))) {
                NSLog(@"Failed to post mouse event");
                exit(0);
            }
            break;
        }
        case DRIVER_QUARTZ:
        {
            CGEventRef evt = CGEventCreateMouseEvent(eventSource, eventType, newPos, otherButton);
            CGEventSetIntegerValueField(evt, kCGMouseEventDeltaX, deltaX);
            CGEventSetIntegerValueField(evt, kCGMouseEventDeltaY, deltaY);
            CGEventPost(kCGSessionEventTap, evt);
            CFRelease(evt);
            break;
        }
        case DRIVER_IOHID:
        {
            int iohidEventType;

            switch (eventType) {
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
                    NSLog(@"INTERNAL ERROR: unknown eventType: %d", eventType);
                    exit(0);
            }

            static NXEventData eventData;
            memset(&eventData, 0, sizeof(NXEventData));

            IOGPoint newPoint = { (SInt16) newPos.x, (SInt16) newPos.y };

            eventData.mouseMove.subType = NX_SUBTYPE_TABLET_POINT;
            eventData.mouseMove.dx = (SInt32)(deltaX);
            eventData.mouseMove.dy = (SInt32)(deltaY);

            (void)IOHIDPostEvent(iohid_connect,
                                 iohidEventType,
                                 newPoint,
                                 &eventData,
                                 kNXEventDataVersion,
                                 0,
                                 kIOHIDSetCursorPosition);
            break;
        }
        default:
        {
            NSLog(@"Driver %d not implemented: ", driver);
            exit(0);
        }
    }

    e2 = GET_TIME();

    currentPos = newPos;
}

static void mouse_handle_buttons(int buttons) {

    CGEventType eventType = kCGEventNull;

    for(int i = 0; i < NUM_BUTTONS; i++) {
        int buttonIndex = (1 << i);
        if (BUTTON_STATE_CHANGED(buttons, lastButtons, buttonIndex)) {
            if (BUTTON_DOWN(buttons, buttonIndex)) {
                switch(buttonIndex) {
                    case LEFT_BUTTON:   eventType = kCGEventLeftMouseDown; break;
                    case RIGHT_BUTTON:  eventType = kCGEventRightMouseDown; break;
                    default:            eventType = kCGEventOtherMouseDown; break;
                }
            } else {
                switch(buttonIndex) {
                    case LEFT_BUTTON:   eventType = kCGEventLeftMouseUp; break;
                    case RIGHT_BUTTON:  eventType = kCGEventRightMouseUp; break;
                    default:            eventType = kCGEventOtherMouseUp; break;
                }
            }

            CGMouseButton otherButton = 0;
            switch(buttonIndex) {
                case LEFT_BUTTON: otherButton = kCGMouseButtonLeft; break;
                case RIGHT_BUTTON: otherButton = kCGMouseButtonRight; break;
                case MIDDLE_BUTTON: otherButton = kCGMouseButtonCenter; break;
                case BUTTON4: otherButton = 3; break;
                case BUTTON5: otherButton = 4; break;
                case BUTTON6: otherButton = 5; break;
            }

            if (eventType == kCGEventLeftMouseDown) {
                CGFloat maxDistanceAllowed = sqrt(2) + 0.0001;
                CGFloat distanceMovedSinceLastClick = get_distance(lastClickPos, currentPos);
                double now = timestamp();

                int theDoubleClickSpeed;
                pthread_mutex_lock(&clickCountMutex);
                theDoubleClickSpeed = doubleClickSpeed;
                pthread_mutex_unlock(&clickCountMutex);

                if (now - lastClickTime <= doubleClickSpeed &&
                    distanceMovedSinceLastClick <= maxDistanceAllowed) {
                    lastClickTime = timestamp();
                    nclicks++;
                } else {
                    nclicks = 1;
                    lastClickTime = timestamp();
                    lastClickPos = currentPos;
                }
            }

            int clickStateValue;
            switch(eventType) {
                case kCGEventLeftMouseDown:
                case kCGEventLeftMouseUp:
                    clickStateValue = nclicks;
                    break;
                case kCGEventRightMouseDown:
                case kCGEventOtherMouseDown:
                case kCGEventRightMouseUp:
                case kCGEventOtherMouseUp:
                    clickStateValue = 1;
                    break;
                default:
                    NSLog(@"INTERNAL ERROR: illegal eventType: %d", eventType);
                    exit(0);
            }

            if (is_debug) {
                LOG(@"buttons(LMR456): %d%d%d%d%d%d, eventType: %s(%d), otherButton: %d, buttonIndex(654LMR): %d, nclicks: %d, csv: %d",
                    BUTTON_DOWN(buttons, LEFT_BUTTON),
                    BUTTON_DOWN(buttons, MIDDLE_BUTTON),
                    BUTTON_DOWN(buttons, RIGHT_BUTTON),
                    BUTTON_DOWN(buttons, BUTTON4),
                    BUTTON_DOWN(buttons, BUTTON5),
                    BUTTON_DOWN(buttons, BUTTON6),
                    event_type_to_string(eventType),
                    eventType,
                    otherButton,
                    ((int)log2(buttonIndex)),
                    nclicks,
                    clickStateValue);
            }

            int driver_to_use = driver;

            // can't get middle mouse to work in iohid, so let's channel all "other" events
            // through quartz
            if (driver == DRIVER_IOHID &&
                (eventType == kCGEventOtherMouseDown || eventType == kCGEventOtherMouseUp)) {
                driver_to_use = DRIVER_QUARTZ;
            }

            e1 = GET_TIME();
            switch (driver_to_use) {
                case DRIVER_QUARTZ_OLD:
                {
                    if (kCGErrorSuccess != CGPostMouseEvent(currentPos, true, 1, BUTTON_DOWN(buttons, LEFT_BUTTON))) {
                        NSLog(@"Failed to post mouse event");
                        exit(0);
                    }
                    break;
                }
                case DRIVER_QUARTZ:
                {
                    CGEventRef evt = CGEventCreateMouseEvent(eventSource, eventType, currentPos, otherButton);
                    CGEventSetIntegerValueField(evt, kCGMouseEventClickState, clickStateValue);
                    CGEventPost(kCGSessionEventTap, evt);
                    CFRelease(evt);
                    break;
                }
                case DRIVER_IOHID:
                {
                    int iohidEventType;

                    switch(eventType) {
                        case kCGEventLeftMouseDown:
                            iohidEventType = NX_LMOUSEDOWN;
                            break;
                        case kCGEventLeftMouseUp:
                            iohidEventType = NX_LMOUSEUP;
                            break;
                        case kCGEventRightMouseDown:
                            iohidEventType = NX_RMOUSEDOWN;
                            break;
                        case kCGEventRightMouseUp:
                            iohidEventType = NX_RMOUSEUP;
                            break;
                        case kCGEventOtherMouseDown:
                            iohidEventType = NX_OMOUSEDOWN;
                            break;
                        case kCGEventOtherMouseUp:
                            iohidEventType = NX_OMOUSEUP;
                            break;
                        default:
                            NSLog(@"INTERNAL ERROR: unknown eventType: %d", eventType);
                            exit(0);
                    }

                    static NXEventData eventData;
                    memset(&eventData, 0, sizeof(NXEventData));

                    eventData.mouse.subType = NX_SUBTYPE_TABLET_POINT;
                    eventData.mouse.click = clickStateValue;
                    eventData.mouse.buttonNumber = otherButton;

                    if (is_debug) {
                        NSLog(@"eventType: %d, subt: %d, click: %d, buttonNumber: %d",
                              iohidEventType,
                              eventData.mouse.subType,
                              eventData.mouse.click,
                              eventData.mouse.buttonNumber);
                    }

                    IOGPoint newPoint = { (SInt16) currentPos.x, (SInt16) currentPos.y };

                    IOHIDPostEvent(iohid_connect,
                                   iohidEventType,
                                   newPoint,
                                   &eventData,
                                   kNXEventDataVersion,
                                   0,
                                   0);

                    break;
                }
                default:
                {
                    NSLog(@"Driver %d not implemented: ", driver);
                    exit(0);
                }
            }

            e2 = GET_TIME();
        }
    }

    lastButtons = buttons;
}

void mouse_handle(mouse_event_t *event) {

    if (event->seqnum != (lastSequenceNumber + 1)) {
        if (is_debug) {
            LOG(@"Cursor position dirty, need to fetch fresh");
        }

        currentPos = get_current_mouse_pos();
    }

    if (event->dx != 0 || event->dy != 0) {
        double velocity;
        AccelerationCurve curve;
        switch (event->device_type) {
            case kDeviceTypeMouse:
                velocity = velocity_mouse;
                curve = curve_mouse;
                break;
            case kDeviceTypeTrackpad:
                velocity = velocity_trackpad;
                curve = curve_trackpad;
                break;
            default:
                velocity = 1;
                NSLog(@"INTERNAL ERROR: device type not mouse or trackpad");
                exit(0);
        }

        mouse_handle_move(event->device_type, event->dx, event->dy, velocity, curve, event->buttons);
    }

    if (event->buttons != lastButtons) {
        mouse_handle_buttons(event->buttons);
    }

    if (is_debug) {
        debug_register_event(event);
    }
    
    lastSequenceNumber = event->seqnum;
    lastButtons = event->buttons;
    lastPos = currentPos;
}
