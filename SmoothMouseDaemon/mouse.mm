
#import "daemon.h"

#include "mouse.h"
#include "debug.h"
#include <sys/time.h>
#include <pthread.h>
#include <IOKit/hidsystem/event_status_driver.h>
#include <IOKit/hidsystem/IOHIDShared.h>

#import "Config.h"

#include "WindowsFunction.hpp"
#include "OSXFunction.hpp"
#include "driver.h"

WindowsFunction *win = NULL;
OSXFunction *osx_mouse = NULL;
OSXFunction *osx_trackpad = NULL;

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
static int needs_refresh = 0;

// NOTE: since we support 32-bit architectures we need to protect assignment
//       to doubleClickSpeed.
static pthread_mutex_t clickSpeedMutex = PTHREAD_MUTEX_INITIALIZER;

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
    CGPoint currentPos;

#if 1
    CGEventRef event = CGEventCreate(NULL);
    currentPos = CGEventGetLocation(event);
    CFRelease(event);
#else
    NSPoint mouseLoc = [NSEvent mouseLocation];
    currentPos.x = mouseLoc.x;
    currentPos.y = mouseLoc.y;
#endif

    //NSLog(@"got cursor position: %f,%f", currentPos.x, currentPos.y);

    // truncate coordinates
    currentPos.x = (int)currentPos.x;
    currentPos.y = (int)currentPos.y;

    return currentPos;
}

static void refresh_mouse_location() {
    CGPoint oldPos = currentPos;
    currentPos = get_current_mouse_pos();

    float movedX = oldPos.x - currentPos.x;
    float movedY = oldPos.y - currentPos.y;

    deltaPosFloat.x += movedX;
    deltaPosFloat.y += movedY;
    deltaPosInt.x += movedX;
    deltaPosInt.y += movedY;
}

void mouse_update_clicktime() {
    pthread_mutex_lock(&clickSpeedMutex);
    NXEventHandle handle = NXOpenEventStatus();
	doubleClickSpeed = NXClickTime(handle);
    NXCloseEventStatus(handle);
    pthread_mutex_unlock(&clickSpeedMutex);
    //NSLog(@"clicktime updated: %f", clickTime);
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

    deltaPosFloat.x += calcdx;
    deltaPosFloat.y += calcdy;
    int deltaX = (int) (deltaPosFloat.x - deltaPosInt.x);
    int deltaY = (int) (deltaPosFloat.y - deltaPosInt.y);
    deltaPosInt.x += deltaX;
    deltaPosInt.y += deltaY;

    newPos.x = currentPos.x + deltaX;
    newPos.y = currentPos.y + deltaY;

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

    if ([[Config instance] debugEnabled]) {
        LOG(@"move dx: %02d, dy: %02d, new pos: %03dx%03d, delta: %02d,%02d, deltaPos: %03dx%03df, buttons(LMR456): %d%d%d%d%d%d, eventType: %s(%d), otherButton: %d",
            dx,
            dy,
            (int)newPos.x,
            (int)newPos.y,
            deltaX,
            deltaY,
            (int)deltaPosInt.x,
            (int)deltaPosInt.y,
            BUTTON_DOWN(currentButtons, LEFT_BUTTON),
            BUTTON_DOWN(currentButtons, MIDDLE_BUTTON),
            BUTTON_DOWN(currentButtons, RIGHT_BUTTON),
            BUTTON_DOWN(currentButtons, BUTTON4),
            BUTTON_DOWN(currentButtons, BUTTON5),
            BUTTON_DOWN(currentButtons, BUTTON6),
            driver_quartz_event_type_to_string(eventType),
            eventType,
            otherButton);
    }

    [sMouseSupervisor pushMouseEvent: deltaX: deltaY];

    driver_event_t event;
    event.id = DRIVER_EVENT_ID_MOVE;
    event.seqnum = lastSequenceNumber + 1; // TODO
    event.move.pos = newPos;
    event.move.type = eventType;
    event.move.deltaX = deltaX;
    event.move.deltaY = deltaY;
    event.move.buttons = currentButtons;
    event.move.otherButton = otherButton;
    driver_post_event((driver_event_t *)&event);

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
                pthread_mutex_lock(&clickSpeedMutex);
                theDoubleClickSpeed = doubleClickSpeed;
                pthread_mutex_unlock(&clickSpeedMutex);

                if (now - lastClickTime <= theDoubleClickSpeed &&
                    distanceMovedSinceLastClick <= maxDistanceAllowed) {
                    lastClickTime = timestamp();
                    nclicks++;
                } else {
                    nclicks = 1;
                    lastClickTime = timestamp();
                    lastClickPos = currentPos;
                }
            }

            if ([[Config instance] debugEnabled]) {
                LOG(@"buttons(LMR456): %d%d%d%d%d%d, eventType: %s(%d), otherButton: %d, buttonIndex(654LMR): %d, nclicks: %d",
                    BUTTON_DOWN(buttons, LEFT_BUTTON),
                    BUTTON_DOWN(buttons, MIDDLE_BUTTON),
                    BUTTON_DOWN(buttons, RIGHT_BUTTON),
                    BUTTON_DOWN(buttons, BUTTON4),
                    BUTTON_DOWN(buttons, BUTTON5),
                    BUTTON_DOWN(buttons, BUTTON6),
                    driver_quartz_event_type_to_string(eventType),
                    eventType,
                    otherButton,
                    ((int)log2(buttonIndex)),
                    nclicks);
            }

            driver_event_t event;
            event.id = DRIVER_EVENT_ID_BUTTON;
            event.seqnum = lastSequenceNumber + 1; // TODO
            event.button.pos = currentPos;
            event.button.type = eventType;
            event.button.buttons = buttons;
            event.button.otherButton = otherButton;
            event.button.nclicks = nclicks;
            driver_post_event((driver_event_t *)&event);
        }
    }
}

void check_needs_refresh(mouse_event_t *event) {
    int seqNumOk = (event->seqnum == (lastSequenceNumber + 1));

    if (needs_refresh || !seqNumOk) {
        if ([[Config instance] debugEnabled]) {
            LOG(@"Cursor position dirty, need to fetch fresh (needs_refresh: %d, seqNumOk: %d)",
                needs_refresh, seqNumOk);
        }

        refresh_mouse_location();

        needs_refresh = 0;
    }
}

void mouse_handle(mouse_event_t *event) {

    check_needs_refresh(event);

    if (event->buttons != lastButtons) {
        mouse_handle_buttons(event->buttons);
    }

    check_needs_refresh(event);

    if (event->dx != 0 || event->dy != 0) {
        double velocity;
        AccelerationCurve curve;
        switch (event->device_type) {
            case kDeviceTypeMouse:
                velocity = [[Config instance] mouseVelocity];
                curve = [[Config instance] mouseCurve];
                break;
            case kDeviceTypeTrackpad:
                velocity = [[Config instance] trackpadVelocity];
                curve = [[Config instance] trackpadCurve];
                break;
            default:
                NSLog(@"INTERNAL ERROR: device type not mouse or trackpad");
                exit(0);
        }

        mouse_handle_move(event->device_type, event->dx, event->dy, velocity, curve, event->buttons);
    }

    if ([[Config instance] debugEnabled]) {
        debug_register_event(event);
    }

    lastSequenceNumber = event->seqnum;
    lastButtons = event->buttons;
    lastPos = currentPos;
}

void mouse_refresh() {
    needs_refresh = 1;
}

BOOL mouse_init() {
    mouse_update_clicktime();

    currentPos = deltaPosFloat = deltaPosInt = get_current_mouse_pos();

    return driver_init();
}

BOOL mouse_cleanup() {
    if (lastButtons != 0) {
        NSLog(@"Force mouse button release");
        mouse_handle_buttons(0);
    }

    if (win != NULL) {
        delete win;
        win = NULL;
    }
    if (osx_mouse != NULL) {
        delete osx_mouse;
        osx_mouse = NULL;
    }
    if (osx_trackpad != NULL) {
        delete osx_trackpad;
        osx_trackpad = NULL;
    }

    return driver_cleanup();
}
