#import <mach/mach.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/IODataQueueShared.h>
#import <IOKit/IODataQueueClient.h>
#import <IOKit/kext/KextManager.h>
#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>

#include <assert.h>
#include <pthread.h>

#import "kextdaemon.h"
#import "constants.h"
#include "debug.h"

#include <IOKit/hidsystem/event_status_driver.h>
#include <IOKit/hidsystem/IOHIDParameter.h>

/* -------------------------------------------------------------------------- */

#define LEFT_BUTTON		4
#define RIGHT_BUTTON	1
#define MIDDLE_BUTTON	2
#define BUTTON4			8
#define BUTTON5			16
#define BUTTON6			32

#define BUTTON_DOWN(state, button) ((button & state) == button)
#define BUTTON_UP(state, button) ((button & state) == button)

/* -------------------------------------------------------------------------- */

static CGPoint pos0;
static BOOL mouse_enabled;
static BOOL trackpad_enabled;
static double velocity_mouse;
static double velocity_trackpad;
static int acceleration_curve_mouse;
static int acceleration_curve_trackpad;
static BOOL is_debug;

/* -------------------------------------------------------------------------- *
 The following code is responsive for handling events received from kernel
 extension and for passing mouse events into CoreGraphics.
 * -------------------------------------------------------------------------- */

/*
 This function handles events received from kernel module.
 */
static void mouse_event_handler(void *buf, unsigned int size) {
	CGPoint pos;
	mouse_event_t *event = buf;
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
	
	/* Save current position */
	pos0 = pos;
	
	/* Post event */
	if (kCGErrorSuccess != CGPostMouseEvent(pos, true, 1, BUTTON_DOWN(event->buttons, LEFT_BUTTON))) {
        NSLog(@"Failed to post mouse event");
		exit(0);
	}

    if (is_debug) {
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
-(void) initializeSystemMouseSettings;
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
    
	if (![self getCursorPosition]) {
		NSLog(@"cannot get cursor position");
		[self dealloc];
		return nil;
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
	if (CGSetLocalEventsFilterDuringSupressionState(kCGEventFilterMaskPermitAllEvents,
													kCGEventSuppressionStateRemoteMouseDrag)) {
		NSLog(@"CGSetLocalEventsFilterDuringSupressionState returns with error");
	}
    
	if (CGSetLocalEventsSuppressionInterval(0.0)) {
		NSLog(@"CGSetLocalEventsSuppressionInterval() returns with error");
	}
}

// NOTE: You can only call this once, when the daemon starts up.
//       if you call it again, for example in mainloop, it will result in null-deltas.
-(void) initializeSystemMouseSettings
{
    NXEventHandle   handle;
    CFStringRef     key;
    kern_return_t   ret;
    double          oldValueMouse,
                    newValueMouse,
                    oldValueTrackpad,
                    newValueTrackpad;
    double          resetValue = 0.0;
    
    handle = NXOpenEventStatus();

    if (mouse_enabled) {
        key = CFSTR(kIOHIDMouseAccelerationType);
        
        ret = IOHIDGetAccelerationWithKey(handle, key, &oldValueMouse);
        if (ret != KERN_SUCCESS) {
            NSLog(@"Failed to get '%@'", key);
            return;
        }
        
        if (oldValueMouse != resetValue) {
            ret = IOHIDSetAccelerationWithKey(handle, key, resetValue);
            if (ret != KERN_SUCCESS) {
                NSLog(@"Failed to disable acceleration for '%@'", key);
            }
        } else if (is_debug) {
            NSLog(@"Skipped settings '%@'", key);
        }
        
        ret = IOHIDGetAccelerationWithKey(handle, key, &newValueMouse);
        if (ret != KERN_SUCCESS) {
            NSLog(@"Failed to get '%@' (2)", key);
            return;
        }

        NSLog(@"System mouse settings initialized (%f/%f)", oldValueMouse, newValueMouse);
    }
    
    if (trackpad_enabled) {
        key = CFSTR(kIOHIDTrackpadAccelerationType);
        
        ret = IOHIDGetAccelerationWithKey(handle, key, &oldValueTrackpad);
        if (ret != KERN_SUCCESS) {
            NSLog(@"Failed to get '%@'", key);
            return;
        }
        
        if (oldValueTrackpad != resetValue) {
            ret = IOHIDSetAccelerationWithKey(handle, key, resetValue);
            if (ret != KERN_SUCCESS) {
                NSLog(@"Failed to disable acceleration for '%@'", key);
            }
        } else if (is_debug) {
            NSLog(@"Skipped settings '%@'", key);
        }
        
        ret = IOHIDGetAccelerationWithKey(handle, key, &newValueTrackpad);
        if (ret != KERN_SUCCESS) {
            NSLog(@"Failed to get '%@' (2)", key);
            return;
        }

        NSLog(@"System trackpad settings initialized (%f/%f)", oldValueTrackpad, newValueTrackpad);
    }

    NXCloseEventStatus(handle);
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
        
        error = IOConnectSetNotificationPort(connect, eMouseEvent, recvPort, 0);
        if (kIOReturnSuccess != error) {
            NSLog(@"IOConnectSetNotificationPort returned %d\n", error);
            goto error;
        }
        
        error = IOConnectMapMemory(connect, eMouseEvent, mach_task_self(), &address, &size, kIOMapAnywhere);
        if (kIOReturnSuccess != error) {
            NSLog(@"IOConnectMapMemory returned %d\n", error);
            goto error;
        }
        
        queueMappedMemory = (IODataQueueMemory *) address;
        dataSize = size;
        
        [self configureDriver];

        int threadError = pthread_create(&mouseEventThreadID, NULL, &HandleMouseEventThread, self);
        if (threadError != 0)
        {
            NSLog(@"Failed to start mouse event thread");
        }

        [self initializeSystemMouseSettings];
        
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
            IOConnectUnmapMemory(connect, eMouseEvent, mach_task_self(), address);
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
        sleep(3);
        BOOL active = [self isActive];
        if (active) {
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

void trap_ctrl_c(int sig)
{
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
    
    if (is_debug) {
        atexit(debug_end);
    }

    signal(SIGINT, trap_ctrl_c);
    
    NSLog(@"Mouse enabled: %d Mouse velocity: %f, Trackpad enabled: %d, Trackpad velocity: %f",
          mouse_enabled,
          velocity_mouse,
          trackpad_enabled,
          velocity_trackpad);

	[daemon mainLoop];
	
	[daemon release];
	
	[pool release];
    
	return EXIT_SUCCESS;
}
