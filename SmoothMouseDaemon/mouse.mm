
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
int totalNumberOfLostEvents = 0;
static int needs_refresh = 0;
static RefreshReason refresh_reason = REFRESH_REASON_UNKNOWN;

static int doubleClickSpeedUpdated = 0;
static double newDoubleClickSpeed;

static int remap_buttons(int buttons) {

    int bl = !!(buttons & 4);
    int bm = !!(buttons & 2);
    int br = !!(buttons & 1);
    int b4 = !!(buttons & 8);
    int b5 = !!(buttons & 16);
    int b6 = !!(buttons & 32);

    int remapped = 0;

    remapped |= (bl << 0);
    remapped |= (br << 1);
    remapped |= (bm << 2);
    remapped |= (b4 << 3);
    remapped |= (b5 << 4);
    remapped |= (b6 << 5);

    return remapped;
}

static const char *get_refresh_reason_string(RefreshReason reason) {
    switch (reason) {
        case REFRESH_REASON_SEQUENCE_NUMBER_INVALID: return "REFRESH_REASON_SEQUENCE_NUMBER_INVALID";
        case REFRESH_REASON_POSITION_TAMPERING: return "REFRESH_REASON_POSITION_TAMPERING";
        case REFRESH_REASON_BUTTON_CLICK: return "REFRESH_REASON_BUTTON_CLICK";
        case REFRESH_REASON_FORCE_DRAG_REFRESH: return "REFRESH_REASON_FORCE_DRAG_REFRESH";
        case REFRESH_REASON_UNKNOWN: return "REFRESH_REASON_UNKNOWN";
        default: return "?";
    }
}

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

    float movedX = currentPos.x - oldPos.x;
    float movedY = currentPos.y - oldPos.y;

    deltaPosFloat.x += movedX;
    deltaPosFloat.y += movedY;
    deltaPosInt.x += movedX;
    deltaPosInt.y += movedY;

    if ([[Config instance] debugEnabled]) {
        LOG(@"Mouse location refreshed (%s), new: %dx%d, old: %dx%d", get_refresh_reason_string(refresh_reason),(int)currentPos.x, (int)currentPos.y, (int)oldPos.x, (int)oldPos.y);
    }
}

void mouse_update_clicktime() {
    // only update once every sec (TODO: prettier)
    // this operation is pretty costly
    static int counter = 0;
    if ((counter++) % 2 == 0) {
        NXEventHandle handle = NXOpenEventStatus();
        newDoubleClickSpeed = NXClickTime(handle);
        NXCloseEventStatus(handle);
        if (newDoubleClickSpeed != doubleClickSpeed) {
            doubleClickSpeedUpdated = 1;
        }
        //NSLog(@"current system double click speed: %f", newDoubleClickSpeed);
    }
}

static void mouse_handle_move(pointing_event_t *event, double velocity, AccelerationCurve curve) {
    CGPoint newPos;

    float calcdx;
    float calcdy;

    if (curve == ACCELERATION_CURVE_WINDOWS) {
        // map prefpane velocity slider to [-5 <=> +5]
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
        win->apply(event->dx, event->dy, &newdx, &newdy);
        calcdx = (float) newdx;
        calcdy = (float) newdy;
    } else if (curve == ACCELERATION_CURVE_OSX) {
        float speed = velocity;
        if (event->is_trackpad && osx_trackpad == NULL) {
            osx_trackpad = new OSXFunction("touchpad", speed);
        } else if (!event->is_trackpad && osx_mouse == NULL) {
            osx_mouse = new OSXFunction("mouse", speed);
        }
        int newdx;
        int newdy;
        OSXFunction *osx = NULL;
        if (event->is_trackpad) {
            osx = osx_trackpad;
        } else {
            osx = osx_mouse;
        }
        osx->apply(event->dx, event->dy, &newdx, &newdy);
        calcdx = (float) newdx;
        calcdy = (float) newdy;
    }
    else {
        calcdx = (velocity * event->dx);
        calcdy = (velocity * event->dy);
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

    if (BUTTON_DOWN(event->buttons, LEFT_BUTTON)) {
        eventType = kCGEventLeftMouseDragged;
        otherButton = kCGMouseButtonLeft;
    } else if (BUTTON_DOWN(event->buttons, RIGHT_BUTTON)) {
        eventType = kCGEventRightMouseDragged;
        otherButton = kCGMouseButtonRight;
    } else if (BUTTON_DOWN(event->buttons, MIDDLE_BUTTON)) {
        eventType = kCGEventOtherMouseDragged;
        otherButton = kCGMouseButtonCenter;
    } else if (BUTTON_DOWN(event->buttons, BUTTON4)) {
        eventType = kCGEventOtherMouseDragged;
        otherButton = 3;
    } else if (BUTTON_DOWN(event->buttons, BUTTON5)) {
        eventType = kCGEventOtherMouseDragged;
        otherButton = 4;
    } else if (BUTTON_DOWN(event->buttons, BUTTON6)) {
        eventType = kCGEventOtherMouseDragged;
        otherButton = 5;
    }

    if ([[Config instance] debugEnabled]) {
        LOG(@"processed move event: move dx: %02d, dy: %02d, new pos: %03dx%03d, delta: %02d,%02d, deltaPosInt: %.02fx%.02f, deltaPosFloat: %.02fx%.02f, buttons(LRM456): %d%d%d%d%d%d, eventType: %s(%d), otherButton: %d",
            event->dx,
            event->dy,
            (int)newPos.x,
            (int)newPos.y,
            deltaX,
            deltaY,
            deltaPosInt.x,
            deltaPosInt.y,
            deltaPosFloat.x,
            deltaPosFloat.y,
            BUTTON_DOWN(event->buttons, LEFT_BUTTON),
            BUTTON_DOWN(event->buttons, RIGHT_BUTTON),
            BUTTON_DOWN(event->buttons, MIDDLE_BUTTON),
            BUTTON_DOWN(event->buttons, BUTTON4),
            BUTTON_DOWN(event->buttons, BUTTON5),
            BUTTON_DOWN(event->buttons, BUTTON6),
            driver_quartz_event_type_to_string(eventType),
            eventType,
            otherButton);
    }

//    if (!(deltaX == 0 && deltaY == 0)) {
        driver_event_t driverEvent;
        driverEvent.id = DRIVER_EVENT_ID_MOVE;
        driverEvent.kextSeqnum = event->base.seq;
        driverEvent.kextTimestamp = event->base.timestamp;
        driverEvent.move.pos = newPos;
        driverEvent.move.type = eventType;
        driverEvent.move.deltaX = deltaX;
        driverEvent.move.deltaY = deltaY;
        driverEvent.move.buttons = event->buttons;
        driverEvent.move.otherButton = otherButton;
        driver_post_event((driver_event_t *)&driverEvent);
//    }

    currentPos = newPos;

    if ([[Config instance] overlayEnabled]) {
        [[Daemon instance] redrawOverlay];
    }

    if (eventType != kCGEventMouseMoved) {
        // some games require the mouse position to be refreshed continuously during drags
        if ([[Config instance] forceDragRefreshEnabled] ||
            [[Config instance] activeAppRequiresRefreshOnDrag]) {
            mouse_refresh(REFRESH_REASON_FORCE_DRAG_REFRESH);
        }
    }
}

static void mouse_handle_buttons(pointing_event_t *event) {

    int buttons;

    if (event != NULL) {
        buttons = event->buttons;
    } else {
        buttons = 0; // all release, we're terminating
    }

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

                if (doubleClickSpeedUpdated) {
                    doubleClickSpeed = newDoubleClickSpeed;
                    doubleClickSpeedUpdated = 0;
                    //NSLog(@"Double click speed updated to %f", doubleClickSpeed);
                }

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

            if ([[Config instance] debugEnabled]) {
                LOG(@"processed button event: buttons(LRM456): %d%d%d%d%d%d, eventType: %s(%d), otherButton: %d, buttonIndex(654MRL): %d, nclicks: %d",
                    BUTTON_DOWN(buttons, LEFT_BUTTON),
                    BUTTON_DOWN(buttons, RIGHT_BUTTON),
                    BUTTON_DOWN(buttons, MIDDLE_BUTTON),
                    BUTTON_DOWN(buttons, BUTTON4),
                    BUTTON_DOWN(buttons, BUTTON5),
                    BUTTON_DOWN(buttons, BUTTON6),
                    driver_quartz_event_type_to_string(eventType),
                    eventType,
                    otherButton,
                    ((int)log2(buttonIndex)),
                    nclicks);
            }

            driver_event_t driverEvent;
            driverEvent.id = DRIVER_EVENT_ID_BUTTON;
            if (event != NULL) {
                driverEvent.kextSeqnum = event->base.seq;
                driverEvent.kextTimestamp = event->base.timestamp;
            } else {
                driverEvent.kextSeqnum = 0;
                driverEvent.kextTimestamp = 0;
            }
            driverEvent.button.pos = currentPos;
            driverEvent.button.type = eventType;
            driverEvent.button.buttons = buttons;
            driverEvent.button.otherButton = otherButton;
            driverEvent.button.nclicks = nclicks;
            driver_post_event((driver_event_t *)&driverEvent);
        }
    }
}

void check_sequence_number(pointing_event_t *event) {
    uint64_t seqnumExpected = (lastSequenceNumber + 1);
    int seqNumOk = (event->base.seq == seqnumExpected);
    uint64_t lostEvents = (event->base.seq - seqnumExpected);
    if (lastSequenceNumber == 0) {
        lostEvents = 0;
    }
    totalNumberOfLostEvents += lostEvents;
    if (!seqNumOk) {
        LOG(@"seqnum: %llu, expected: %llu (%llu lost events)",
            event->base.seq,
            seqnumExpected,
            lostEvents);
        if (lostEvents != 0 && [[Config instance] sayEnabled]) {
            NSString *stringToSay;
            if (lostEvents == 1) {
                stringToSay = [NSString stringWithFormat:@"Lost 1 kernel event"];
            } else {
                stringToSay = [NSString stringWithFormat:@"Lost %d kernel events", (int)lostEvents];
            }
            [[Daemon instance] say: stringToSay];
            [stringToSay release];
        }
        mouse_refresh(REFRESH_REASON_SEQUENCE_NUMBER_INVALID);
    }
}

void check_needs_refresh(pointing_event_t *event) {
    if (needs_refresh) {
        refresh_mouse_location();
        needs_refresh = 0;
    }
}

void mouse_process_kext_event(pointing_event_t *event) {

    event->buttons = remap_buttons(event->buttons);

    check_sequence_number(event);

    if (event->buttons != lastButtons) {
        check_needs_refresh(event);
        mouse_handle_buttons(event);

        // on all clicks, refresh mouse position
        mouse_refresh(REFRESH_REASON_BUTTON_CLICK);
    }

    if (event->dx != 0 || event->dy != 0) {
        check_needs_refresh(event);
        double velocity;
        AccelerationCurve curve;
        if (!event->is_trackpad) {
            velocity = [[Config instance] mouseVelocity];
            curve = [[Config instance] mouseCurve];
        } else {
            velocity = [[Config instance] trackpadVelocity];
            curve = [[Config instance] trackpadCurve];
        }

        mouse_handle_move(event, velocity, curve);
    } else {
        LOG(@"WARNING: pointing null delta event");
    }

    lastSequenceNumber = event->base.seq;
    lastButtons = event->buttons;
    lastPos = currentPos;
}

void mouse_refresh(RefreshReason reason) {
    if (needs_refresh != 1) {
        needs_refresh = 1;
        refresh_reason = reason;
    }
}

BOOL mouse_init() {
    mouse_update_clicktime();

    currentPos = deltaPosFloat = deltaPosInt = get_current_mouse_pos();

    lastSequenceNumber = 0;
    totalNumberOfLostEvents = 0;

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

CGPoint mouse_get_current_pos() {
    return currentPos;
}

