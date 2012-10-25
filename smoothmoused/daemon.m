#import <mach/mach.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/IODataQueueShared.h>
#import <IOKit/IODataQueueClient.h>
#import <IOKit/kext/KextManager.h>
#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#include <sys/time.h>   
#include <assert.h>
#include <pthread.h>
#include <IOKit/hidsystem/event_status_driver.h>

#import "kextdaemon.h"
#import "constants.h"
#include "debug.h"
#import "accel_util.h"

/* -------------------------------------------------------------------------- */

#define LEFT_BUTTON     4
#define RIGHT_BUTTON    1
#define MIDDLE_BUTTON   2
#define BUTTON4         8
#define BUTTON5         16
#define BUTTON6         32
#define NUM_BUTTONS     6

#define BUTTON_DOWN(button)             (((button) & buttons) == (button))
#define BUTTON_UP(button)               (((button) & buttons) == 0)
#define BUTTON_STATE_CHANGED(button)    ((buttons0 & (button)) != (buttons & (button)))

/* -------------------------------------------------------------------------- */

BOOL is_debug;
BOOL is_event = 0;

static CGPoint pos0;
static int buttons0 = 0;
static CGPoint lastSingleClickPos;
static CGPoint lastDoubleClickPos;
static CGPoint lastTrippleClickPos;
static double lastSingleClick;
static double lastDoubleClick;
static double lastTrippleClick;
static double clickTime;
CGEventType mouseType = kCGEventMouseMoved;
static BOOL mouse_enabled;
static BOOL trackpad_enabled;
static double velocity_mouse;
static double velocity_trackpad;

double timestamp()
{
	struct timeval t;
	gettimeofday(&t, NULL);
	return (double)t.tv_sec + 1.0e-6 * (double)t.tv_usec;
}

/* -------------------------------------------------------------------------- *
 The following code is responsive for handling events received from kernel
 extension and for passing mouse events into CoreGraphics.
 * -------------------------------------------------------------------------- */

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

/*
 This function handles events received from kernel module.
 */
static void mouse_event_handler(void *buf, unsigned int size) {
	CGPoint pos;
	mouse_event_t *event = buf;
    int buttons = event->buttons;
    CGDisplayCount displayCount = 0;
	double velocity = 1;
        
    switch (event->device_type) {
        case kDeviceTypeMouse:
            velocity = velocity_mouse;
            break;
        case kDeviceTypeTrackpad:
            velocity = velocity_trackpad;
            break;
        default:
            velocity = 1;
            NSLog(@"INTERNAL ERROR: device type not mouse or trackpad");
    }
    
    float calcdx = (velocity * event->dx);
	float calcdy = (velocity * event->dy);
    
    /* Calculate new cursor position */
    pos.x = pos0.x + calcdx;
    pos.y = pos0.y + calcdy;
        
	/*
	 The following code checks if cursor is in screen borders. It was ported
	 from Synergy.
	 */
	CGGetDisplaysWithPoint(pos, 0, NULL, &displayCount);
	if (displayCount == 0) {
		displayCount = 0;
		CGDirectDisplayID displayID;
		CGGetDisplaysWithPoint(pos0, 1,
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

	if (is_event) {
        CGMouseButton otherButton = 0;
        int changedIndex = -1;
        int buttonWasReleased = 0;
        int click = 0;
        for(int i = 0; i < NUM_BUTTONS; i++) {
            int buttonIndex = (1 << i);
            if (BUTTON_STATE_CHANGED(buttonIndex)) {
                if (BUTTON_DOWN(buttonIndex)) {
                    switch(buttonIndex) {
                        case LEFT_BUTTON:   mouseType = kCGEventLeftMouseDown; click = 1; break;
                        case RIGHT_BUTTON:  mouseType = kCGEventRightMouseDown; break;
                        default:            mouseType = kCGEventOtherMouseDown; break;
                    }
                } else {
                    switch(buttonIndex) {
                        case LEFT_BUTTON:   mouseType = kCGEventLeftMouseUp; break;
                        case RIGHT_BUTTON:  mouseType = kCGEventRightMouseUp; break;
                        default:            mouseType = kCGEventOtherMouseUp; break;
                    }
                    buttonWasReleased = 1;
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

        if(changedIndex != -1) {
            switch(changedIndex) {
                case LEFT_BUTTON: otherButton = kCGMouseButtonLeft; break;
                case RIGHT_BUTTON: otherButton = kCGMouseButtonRight; break;
                case MIDDLE_BUTTON: otherButton = kCGMouseButtonCenter; break;
                case BUTTON4: otherButton = 0; break;
                case BUTTON5: otherButton   = 0; break;
                case BUTTON6: otherButton = 0; break;
            }
        }

        int is_double_click = 0;
        int is_tripple_click = 0;
        if (click) {
            CGFloat maxDistanceAllowed = sqrt(2) + 0.0001;
            CGFloat distanceMovedSinceLastSingleClick = get_distance(lastSingleClickPos, pos);
            CGFloat distanceMovedSinceLastDoubleClick = get_distance(lastDoubleClickPos, pos);
            CGFloat distanceMovedSinceLastTrippleClick = get_distance(lastTrippleClickPos, pos);
            double now = timestamp();
            if (now - lastTrippleClick <= clickTime &&
                distanceMovedSinceLastTrippleClick <= maxDistanceAllowed) {
                lastTrippleClick = timestamp();
                click = 0;
                mouseType = kCGEventMouseMoved;
            } else if((now - lastDoubleClick <= clickTime) &&
                distanceMovedSinceLastDoubleClick <= maxDistanceAllowed) {
                is_tripple_click = 1;
                lastTrippleClick = timestamp();
                lastTrippleClickPos = pos;
            } else if ((now - lastSingleClick <= clickTime) &&
                distanceMovedSinceLastSingleClick <= maxDistanceAllowed) {
                is_double_click = 1;
                lastDoubleClick = timestamp();
                lastDoubleClickPos = pos;
            } else {
                lastSingleClick = timestamp();
                lastSingleClickPos = pos;
            }
        }
        
        if (is_debug) {
            NSLog(@"dx: %d, dy: %d, buttons(LMR456): %d%d%d%d%d%d, mouseType: %s, otherButton: %d, changedIndex: %d, 123: %d%d%d",
                  event->dx,
                  event->dy,
                  BUTTON_DOWN(LEFT_BUTTON),
                  BUTTON_DOWN(MIDDLE_BUTTON),
                  BUTTON_DOWN(RIGHT_BUTTON),
                  BUTTON_DOWN(BUTTON4),
                  BUTTON_DOWN(BUTTON5),
                  BUTTON_DOWN(BUTTON6),
                  event_type_to_string(mouseType),
                  otherButton,
                  changedIndex,
                  click,
                  is_double_click,
                  is_tripple_click);
        }

        CGEventRef evt = CGEventCreateMouseEvent(NULL, mouseType, pos, otherButton);
        if (is_tripple_click) {
            CGEventSetIntegerValueField(evt, kCGMouseEventClickState, 3);
            CGEventPost(kCGSessionEventTap, evt);
            CGEventSetType(evt, kCGEventLeftMouseUp);
            CGEventPost(kCGSessionEventTap, evt);
        } else if (is_double_click) {
            CGEventSetIntegerValueField(evt, kCGMouseEventClickState, 2);
            CGEventPost(kCGSessionEventTap, evt);
            CGEventSetType(evt, kCGEventLeftMouseUp);
            CGEventPost(kCGSessionEventTap, evt);            
        } else {
            CGEventPost(kCGSessionEventTap, evt);
        }
        CFRelease(evt);

        if(buttonWasReleased) {
            mouseType = kCGEventMouseMoved;
        }

        pos0 = pos;
        buttons0 = event->buttons;
    } else {
        /* post event */
        if (kCGErrorSuccess != CGPostMouseEvent(pos, true, 1, BUTTON_DOWN(LEFT_BUTTON))) {
            NSLog(@"Failed to post mouse event");
            exit(0);
        }
    }
    if (is_debug && !is_event) {
        debug_log(event, calcdx, calcdy);
    }
}

pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;

@interface SmoothMouseDaemon : NSObject {
@private
    BOOL connected;
    pthread_t mouseEventThreadID;
    io_service_t service;
	io_connect_t connect;
	IODataQueueMemory *queueMappedMemory;
	mach_port_t	recvPort;
	uint32_t dataSize;
#if !__LP64__ || defined(IOCONNECT_MAPMEMORY_10_6)
    vm_address_t address;
    vm_size_t size;
#else
	mach_vm_address_t address;
    mach_vm_size_t size;
#endif
}

-(id)init;
-(oneway void) release;

-(BOOL) loadSettings;
-(BOOL) getCursorPosition;
-(BOOL) loadDriver;
-(BOOL) connectToDriver;
-(BOOL) configureDriver;
-(BOOL) disconnectFromDriver;
-(void) setupEventSuppression;
-(BOOL) isActive;

@end

/* -------------------------------------------------------------------------- */

@implementation SmoothMouseDaemon

-(id)init
{
	self = [super init];
	
    connected = NO;
    
	BOOL settingsOK = [self loadSettings];
    if (!settingsOK) {
        NSLog(@"settings doesn't exist (please open preference pane)");
        [self dealloc];
        return nil;
    }
    
    if (!is_debug) {
        if (!mouse_enabled && !trackpad_enabled) {
            NSLog(@"neither mouse nor trackpad is enabled");
            [self dealloc];
            return nil;
        }
    } else {
        mouse_enabled = 1;
        trackpad_enabled = 1;
    }
    
	[self setupEventSuppression];
	
	if (![self connectToDriver]) {
		NSLog(@"cannot connect to driver");
		[self dealloc];
		return nil;
	}
	
	return self;
}

-(BOOL) getCursorPosition
{
	CGEventRef event;
	
	event = CGEventCreate(NULL);
	if (!event) {
		return NO;
	}
	
	pos0 = CGEventGetLocation(event);
	
	CFRelease(event);
	
	return YES;
}

-(void) setupEventSuppression
{
    if (!is_event) {
        if (CGSetLocalEventsFilterDuringSupressionState(kCGEventFilterMaskPermitAllEvents,
                                                        kCGEventSuppressionStateRemoteMouseDrag)) {
            NSLog(@"CGSetLocalEventsFilterDuringSupressionState returns with error");
        }
        
        if (CGSetLocalEventsSuppressionInterval(0.0)) {
            NSLog(@"CGSetLocalEventsSuppressionInterval() returns with error");
        }
    }
}

-(BOOL) loadSettings
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PREFERENCES_FILENAME];
	NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:file];
	
	if (!dict) {
		NSLog(@"cannot open file %@", file);
        return NO;
	}
    
    NSNumber *value;
    
    value = [dict valueForKey:SETTINGS_MOUSE_ENABLED];
	if (value) {
		mouse_enabled = [value boolValue];
	} else {
		return NO;
	}
    
    value = [dict valueForKey:SETTINGS_TRACKPAD_ENABLED];
	if (value) {
		trackpad_enabled = [value boolValue];
	} else {
		return NO;
	}
    
	value = [dict valueForKey:SETTINGS_MOUSE_VELOCITY];
	if (value) {
        velocity_mouse = [value doubleValue];
	} else {
		velocity_mouse = 1.0;
	}
    
    value = [dict valueForKey:SETTINGS_TRACKPAD_VELOCITY];
	if (value) {
		velocity_trackpad = [value doubleValue];
	} else {
		velocity_trackpad = 1.0;
	}

    value = [dict valueForKey:SETTINGS_EVENT_ENABLED];
	if (value) {
		is_event = [value boolValue];
	} else {
		is_event = 0;
	}
    
    return YES;
}

-(BOOL) loadDriver
{
	NSString *kextID = @"com.cyberic.smoothmouse";
	return (kOSReturnSuccess == KextManagerLoadKextWithIdentifier((CFStringRef)kextID, NULL));
}

-(BOOL) connectToDriver
{
    if (!connected) {
        kern_return_t error;
        
        pthread_mutex_lock(&mutex);
        
        service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("com_cyberic_SmoothMouse"));
        if (service == IO_OBJECT_NULL) {
            NSLog(@"IOServiceGetMatchingService() failed");
            if ([self loadDriver]) {
                NSLog(@"driver is loaded manually, try again");
                service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("com_cyberic_SmoothMouse"));
                if (service == IO_OBJECT_NULL) {
                    goto error;
                }
            } else {
                NSLog(@"cannot load driver manually");
            }
            
            goto error;
        }
        
        error = IOServiceOpen(service, mach_task_self(), 0, &connect);
        if (error) {
            NSLog(@"IOServiceOpen() failed");
            IOObjectRelease(service);
            goto error;
        }
        
        IOObjectRelease(service);
        
        recvPort = IODataQueueAllocateNotificationPort();
        if (MACH_PORT_NULL == recvPort) {
            NSLog(@"IODataQueueAllocateNotificationPort returned a NULL mach_port_t\n");
            goto error;
        }
        
        error = IOConnectSetNotificationPort(connect, kIODefaultMemoryType, recvPort, 0);
        if (kIOReturnSuccess != error) {
            NSLog(@"IOConnectSetNotificationPort returned %d\n", error);
            goto error;
        }
        
        error = IOConnectMapMemory(connect, kIODefaultMemoryType, mach_task_self(), &address, &size, kIOMapAnywhere);
        if (kIOReturnSuccess != error) {
            NSLog(@"IOConnectMapMemory returned %d\n", error);
            goto error;
        }
        
        queueMappedMemory = (IODataQueueMemory *) address;
        dataSize = size;
        
        [self configureDriver];
        [self getCursorPosition];

        int threadError = pthread_create(&mouseEventThreadID, NULL, &HandleMouseEventThread, self);
        if (threadError != 0)
        {
            NSLog(@"Failed to start mouse event thread");
        }

        initializeSystemMouseSettings(mouse_enabled, trackpad_enabled);

        connected = YES;
        
        pthread_mutex_unlock(&mutex);
    }

	return YES;

error:
    pthread_mutex_unlock(&mutex);
    return NO;
}

-(BOOL) configureDriver
{
    kern_return_t	kernResult;
	
    uint64_t scalarI_64[1];
    uint64_t scalarO_64;
    uint32_t outputCount = 1;
    
    uint32_t configuration = 0;
    
    if (mouse_enabled) {
        configuration |= 1 << 0;
    }
    
    if (trackpad_enabled) {
        configuration |= 1 << 1;
    }
    
    scalarI_64[0] = configuration;
    
    kernResult = IOConnectCallScalarMethod(connect,					// an io_connect_t returned from IOServiceOpen().
                                           kConfigureMethod,        // selector of the function to be called via the user client.
                                           scalarI_64,				// array of scalar (64-bit) input values.
                                           1,						// the number of scalar input values.
                                           &scalarO_64,				// array of scalar (64-bit) output values.
                                           &outputCount				// pointer to the number of scalar output values.
                                           );
    
    if (kernResult == KERN_SUCCESS) {
        NSLog(@"Driver configured successfully (%u)", (uint32_t) scalarO_64);
        return YES;
    }
	else {
		NSLog(@"Failed to configure driver");
        return NO;
    }
}

-(BOOL) disconnectFromDriver
{
    if (connected) {
        
        pthread_mutex_lock(&mutex);

        if (address) {
            IOConnectUnmapMemory(connect, kIODefaultMemoryType, mach_task_self(), address);
        }

        if (recvPort) {
            mach_port_destroy(mach_task_self(), recvPort);
        }

        if (connect) {
            IOServiceClose(connect);
        }

        connected = NO;
                
        pthread_mutex_unlock(&mutex);

        int rv = pthread_join(mouseEventThreadID, NULL);
        if (rv != 0) {
            NSLog(@"Failed to wait for mouse event thread");
        }
    }
    
    return YES;
}

-(oneway void) release
{
    [self disconnectFromDriver];
	[super release];
}

void *HandleMouseEventThread(void *instance)
{
    SmoothMouseDaemon *self = (SmoothMouseDaemon *) instance;

    kern_return_t error;
    
	char *buf = malloc(self->dataSize);
	if (!buf) {
		NSLog(@"malloc error");
		return NULL;
	}

    NXEventHandle handle = NXOpenEventStatus();
	clickTime = NXClickTime(handle);
    
    while (IODataQueueWaitForAvailableData(self->queueMappedMemory, self->recvPort) == kIOReturnSuccess) {
        
        pthread_mutex_lock(&mutex);

        if (self->connected) {

            while (IODataQueueDataAvailable(self->queueMappedMemory)) {
                error = IODataQueueDequeue(self->queueMappedMemory, buf, &(self->dataSize));
                if (!error) {
                    mouse_event_handler(buf, self->dataSize);
                } else {
                    NSLog(@"IODataQueueDequeue() failed");
                }
            }
        }
        
        pthread_mutex_unlock(&mutex);
    }
    
	free(buf);
    
    return NULL;
}

-(void) mainLoop
{
    while(1) {
        sleep(2);
        BOOL active = [self isActive];
        if (active) {
            initializeSystemMouseSettings(mouse_enabled, trackpad_enabled);
            [self connectToDriver];
        } else {
            [self disconnectFromDriver];
        }
    }
}

-(BOOL) isActive {
#if 1
    CFDictionaryRef dict = CGSessionCopyCurrentDictionary();
    const void* logged_in = CFDictionaryGetValue(dict, kCGSessionOnConsoleKey);
    if (logged_in != kCFBooleanTrue) {
        return NO;
    } else {
        return YES;
    }
#else
    static int i = 0;
    i++;
    if (i % 2 == 0) {
        return NO;
    } else {
        return YES;
    }
#endif
}

@end

void trap_signals(int sig)
{
    //NSLog(@"trapped signal: %d", sig);
    if (is_debug) {
        debug_end();
    }
    if (!is_debug) {
        // TODO: somehow this causes segmentation fault in debug mode
        restoreSystemMouseSettings();
    }
    exit(0);
}

int main(int argc, char **argv)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    is_debug = 0;
    
    if (argc > 1) {
        if (strcmp(argv[1], "--debug") == 0) {
            is_debug = 1;
            NSLog(@"Debug mode on");
        }
    }
    
	SmoothMouseDaemon *daemon = [[SmoothMouseDaemon alloc] init];
    if (daemon == NULL) {
        NSLog(@"Daemon failed to initialize. BYE.");
        exit(-1);
    }
    
#if 0
    for (int i = 0; i != 31; ++i) {
        signal(i, trap_signals);
    }
#endif
    
    signal(SIGINT, trap_signals);
    signal(SIGKILL, trap_signals);
    signal(SIGTERM, trap_signals);
    
    NSLog(@"Mouse enabled: %d Mouse velocity: %f, Trackpad enabled: %d, Trackpad velocity: %f, Event system enabled: %d",
          mouse_enabled,
          velocity_mouse,
          trackpad_enabled,
          velocity_trackpad,
          is_event);

	[daemon mainLoop];
	
	[daemon release];
	
	[pool release];
    
	return EXIT_SUCCESS;
}
