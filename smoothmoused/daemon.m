#import <mach/mach.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/IODataQueueShared.h>
#import <IOKit/IODataQueueClient.h>
#import <IOKit/kext/KextManager.h>
#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>

#import "kextdaemon.h"
#import "constants.h"

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
	if (kCGErrorSuccess != CGPostMouseEvent(pos, true, 6,
											BUTTON_DOWN(event->buttons, LEFT_BUTTON),
											BUTTON_DOWN(event->buttons, RIGHT_BUTTON),
											BUTTON_DOWN(event->buttons, MIDDLE_BUTTON),
											BUTTON_DOWN(event->buttons, BUTTON4),
											BUTTON_DOWN(event->buttons, BUTTON5),
											BUTTON_DOWN(event->buttons, BUTTON6))) {
        NSLog(@"Failed to post mouse event");
		exit(0);
	}
    
    if (is_debug) {
        static long long lastTimestamp = 0;
        static CGPoint lastPoint = { 0, 0 };

        CGEventRef evt = CGEventCreate(NULL);
        CGPoint point = CGEventGetLocation(evt);
        
        if (lastTimestamp != 0) {
            float deltaTimestamp = event->timestamp - lastTimestamp; // timestamp is ns
            
            float actualdx = point.x - lastPoint.x;
            float actualdy = point.y - lastPoint.y;
            
            BOOL inconsistencyDetected = (abs(actualdx - calcdx) > 0.1) || (abs(actualdy - calcdy) > 0.1);
            NSLog(@"Kext: %d ⨉ %d	Calc: %.2f ⨉ %.2f	Move: %.2f ⨉ %.2f	%d Hz	%s",
                  event->dx,
                  event->dy,
                  calcdx,
                  calcdy,
                  actualdx,
                  actualdy,
                  (int) (1000000000 / deltaTimestamp),
                  inconsistencyDetected ? "INCONSISTENCY!" : "");
        }
        lastTimestamp = event->timestamp;
        lastPoint = point;
        
        CFRelease(evt);
    }
}

@interface SmoothMouseDaemon : NSObject {
@private
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
-(void) listenForMouseEvents;
-(void) setupEventSuppression;

@end

/* -------------------------------------------------------------------------- */

@implementation SmoothMouseDaemon

-(id)init
{
	self = [super init];
	
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

-(BOOL) loadSettings
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
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
    
    NSLog(@"Mouse enabled: %d", mouse_enabled);
    NSLog(@"Mouse enabled: %d", trackpad_enabled);
    NSLog(@"Mouse velocity: %f", velocity_mouse);
    NSLog(@"Trackpad velocity: %f", velocity_trackpad);
    
    return YES;
}

-(BOOL) loadDriver
{
	NSString *kextID = @"com.cyberic.smoothmouse";
	return (kOSReturnSuccess == KextManagerLoadKextWithIdentifier((CFStringRef)kextID, NULL));
}

-(BOOL) connectToDriver
{
    kern_return_t error;
	
	service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("com_cyberic_SmoothMouse"));
	if (service == IO_OBJECT_NULL) {
		NSLog(@"IOServiceGetMatchingService() failed");
		if ([self loadDriver]) {
			NSLog(@"driver is loaded manually, try again");
			service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("com_cyberic_SmoothMouse"));
			if (service == IO_OBJECT_NULL) {
				return NO;
			}
		} else {
			NSLog(@"cannot load driver manually");
		}
		
		return NO;
	}
    
	error = IOServiceOpen(service, mach_task_self(), 0, &connect);
	if (error) {
		NSLog(@"IOServiceOpen() failed");
		IOObjectRelease(service);
        return NO;
	}
	
	IOObjectRelease(service);
	
	recvPort = IODataQueueAllocateNotificationPort();
    if (MACH_PORT_NULL == recvPort) {
        NSLog(@"IODataQueueAllocateNotificationPort returned a NULL mach_port_t\n");
        return NO;
    }
    
    error = IOConnectSetNotificationPort(connect, eMouseEvent, recvPort, 0);
    if (kIOReturnSuccess != error) {
        NSLog(@"IOConnectSetNotificationPort returned %d\n", error);
        return NO;
    }
    
    error = IOConnectMapMemory(connect, eMouseEvent, mach_task_self(), &address, &size, kIOMapAnywhere);
    if (kIOReturnSuccess != error) {
        NSLog(@"IOConnectMapMemory returned %d\n", error);
        return NO;
    }
    
    queueMappedMemory = (IODataQueueMemory *) address;
    dataSize = size;
	
    configure_driver(connect);
    
	return YES;
}

BOOL configure_driver(io_connect_t connect)
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

-(oneway void) release
{
	if (address) {
		IOConnectUnmapMemory(connect, eMouseEvent, mach_task_self(), address);
	}
    
	if (recvPort) {
		mach_port_destroy(mach_task_self(), recvPort);
	}
	
	if (connect) {
		IOServiceClose(connect);
	}
	
	[super release];
}

-(void) initializeSystemMouseSettings
{
    NXEventHandle handle;
    CFStringRef key;
    kern_return_t ret;
    
    handle = NXOpenEventStatus();
    
    key = CFSTR(kIOHIDTrackpadAccelerationType);
    ret = IOHIDSetAccelerationWithKey(handle, key, 0.0);
    if (ret != KERN_SUCCESS) {
        NSLog(@"Failed to disable acceleration for trackpad");
    }
    
    key = CFSTR(kIOHIDMouseAccelerationType);
    ret = IOHIDSetAccelerationWithKey(handle, key, 0.0);
    if (ret != KERN_SUCCESS) {
        NSLog(@"Failed to disable acceleration for mouse");
    }
    
    NXCloseEventStatus(handle);
}

-(void) listenForMouseEvents
{
	kern_return_t error;
	char *buf = malloc(dataSize);
	if (!buf) {
		NSLog(@"malloc error");
		return;
	}
    
    while (IODataQueueWaitForAvailableData(queueMappedMemory, recvPort) == kIOReturnSuccess) {
        while (IODataQueueDataAvailable(queueMappedMemory)) {
            error = IODataQueueDequeue(queueMappedMemory, buf, &dataSize);
            if (!error) {
				mouse_event_handler(buf, dataSize);
			} else {
				NSLog(@"IODataQueueDequeue() failed");
			}
        }
    }
	
	free(buf);
}

@end


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
        exit(1);
    }
    
    [daemon initializeSystemMouseSettings];
    
	[daemon listenForMouseEvents];
	
	[daemon release];
	
	[pool release];
    
	return EXIT_SUCCESS;
}
