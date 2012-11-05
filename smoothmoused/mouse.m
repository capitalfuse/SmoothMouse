
#include "mouse.h"
#include "debug.h"

#include <sys/time.h>
#include <IOKit/hidsystem/event_status_driver.h>


#define LEFT_BUTTON     4
#define RIGHT_BUTTON    1
#define MIDDLE_BUTTON   2
#define BUTTON4         8
#define BUTTON5         16
#define BUTTON6         32
#define NUM_BUTTONS     6

#define BUTTON_DOWN(button)             (((button) & event->buttons) == (button))
#define BUTTON_UP(button)               (((button) & event->buttons) == 0)
#define BUTTON_STATE_CHANGED(button)    ((buttons0 & (button)) != (event->buttons & (button)))

extern BOOL is_debug;
extern BOOL is_event;

static CGEventSourceRef eventSource = NULL;
static CGPoint pos0;
static int buttons0 = 0;
static int nclicks = 0;
static CGPoint lastClickPos;
static double lastClickTime = 0;
static double clickTime;

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

static char *event_type_to_string(CGEventType type) {
    switch(type) {
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

bool mouse_init() {

    NXEventHandle handle = NXOpenEventStatus();
	clickTime = NXClickTime(handle);
    NXCloseEventStatus(handle);
    
    eventSource = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    if (eventSource == NULL) {
        NSLog(@"call to CGEventSourceSetKeyboardType failed");
    } else {
        CGEventSourceSetLocalEventsSuppressionInterval(eventSource, 0.0);
        CGEventSourceSetLocalEventsFilterDuringSuppressionState(eventSource, kCGEventFilterMaskPermitLocalMouseEvents, kCGEventSuppressionStateSuppressionInterval);
    }

    CGEventRef event;

	event = CGEventCreate(NULL);
	if (!event) {
		return NO;
	}
	
	pos0 = CGEventGetLocation(event);
	
	CFRelease(event);
	
    if (!is_event) {
        if (CGSetLocalEventsFilterDuringSuppressionState(kCGEventFilterMaskPermitAllEvents,
                                                         kCGEventSuppressionStateRemoteMouseDrag)) {
            NSLog(@"call to CGSetLocalEventsFilterDuringSuppressionState failed");
        }
        
        if (CGSetLocalEventsSuppressionInterval(0.0)) {
            NSLog(@"call to CGSetLocalEventsSuppressionInterval failed");
        }
    }

	return YES;
}

void mouse_cleanup() {
    CFRelease(eventSource);
}

/*
 This function handles events received from kernel module.
 */
void mouse_handle(mouse_event_t *event, double velocity) {
	CGPoint pos;

    float calcdx = (velocity * event->dx);
	float calcdy = (velocity * event->dy);

    /* Calculate new cursor position */
    pos.x = pos0.x + calcdx;
    pos.y = pos0.y + calcdy;

    pos = restrict_to_screen_boundaries(pos0, pos);

	if (is_event) {
        CGEventType mouseType = kCGEventMouseMoved;
        int changedIndex = -1;
        for(int i = 0; i < NUM_BUTTONS; i++) {
            int buttonIndex = (1 << i);
            if (BUTTON_STATE_CHANGED(buttonIndex)) {
                if (BUTTON_DOWN(buttonIndex)) {
                    switch(buttonIndex) {
                        case LEFT_BUTTON:   mouseType = kCGEventLeftMouseDown; break;
                        case RIGHT_BUTTON:  mouseType = kCGEventRightMouseDown; break;
                        default:            mouseType = kCGEventOtherMouseDown; break;
                    }
                } else {
                    switch(buttonIndex) {
                        case LEFT_BUTTON:   mouseType = kCGEventLeftMouseUp; break;
                        case RIGHT_BUTTON:  mouseType = kCGEventRightMouseUp; break;
                        default:            mouseType = kCGEventOtherMouseUp; break;
                    }
                }
                changedIndex = buttonIndex;
            } else {
                if (BUTTON_DOWN(buttonIndex)) {
                    switch(buttonIndex) {
                        case LEFT_BUTTON:   mouseType = kCGEventLeftMouseDragged; break;
                        case RIGHT_BUTTON:  mouseType = kCGEventRightMouseDragged; break;
                        default:            mouseType = kCGEventOtherMouseDragged; break;
                    }
                    changedIndex = buttonIndex;
                }
            }
        }
        
        CGMouseButton otherButton = 0;
        if(changedIndex != -1) {
            switch(changedIndex) {
                case LEFT_BUTTON: otherButton = kCGMouseButtonLeft; break;
                case RIGHT_BUTTON: otherButton = kCGMouseButtonRight; break;
                case MIDDLE_BUTTON: otherButton = kCGMouseButtonCenter; break;
                case BUTTON4: otherButton = 3; break;
                case BUTTON5: otherButton = 4; break;
                case BUTTON6: otherButton = 5; break;
            }
        }
        
        if (mouseType == kCGEventLeftMouseDown) {
            CGFloat maxDistanceAllowed = sqrt(2) + 0.0001;
            CGFloat distanceMovedSinceLastClick = get_distance(lastClickPos, pos);
            double now = timestamp();
            if (now - lastClickTime <= clickTime &&
                distanceMovedSinceLastClick <= maxDistanceAllowed) {
                lastClickTime = timestamp();
                nclicks++;
            } else {
                nclicks = 1;
                lastClickTime = timestamp();
                lastClickPos = pos;
            }
        }
        
        int clickStateValue;
        switch(mouseType) {
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
                clickStateValue = 0;
                break;
        }

        if (is_debug) {
            NSLog(@"dx: %d, dy: %d, buttons(LMR456): %d%d%d%d%d%d, mouseType: %s(%d), otherButton: %d, changedIndex: %d, nclicks: %d, csv: %d",
                  event->dx,
                  event->dy,
                  BUTTON_DOWN(LEFT_BUTTON),
                  BUTTON_DOWN(MIDDLE_BUTTON),
                  BUTTON_DOWN(RIGHT_BUTTON),
                  BUTTON_DOWN(BUTTON4),
                  BUTTON_DOWN(BUTTON5),
                  BUTTON_DOWN(BUTTON6),
                  event_type_to_string(mouseType),
                  mouseType,
                  otherButton,
                  changedIndex,
                  nclicks,
                  clickStateValue);
        }

        CGEventRef evt = CGEventCreateMouseEvent(eventSource, mouseType, pos, otherButton);
        CGEventSetIntegerValueField(evt, kCGMouseEventClickState, clickStateValue);
        CGEventPost(kCGSessionEventTap, evt);
        CFRelease(evt);

    } else {
        /* post event */
        if (kCGErrorSuccess != CGPostMouseEvent(pos, true, 1, BUTTON_DOWN(LEFT_BUTTON))) {
            NSLog(@"Failed to post mouse event");
            exit(0);
        }
    }

    pos0 = pos;
    buttons0 = event->buttons;
    if (is_debug && !is_event) {
        debug_log(event, calcdx, calcdy);
    }
}
