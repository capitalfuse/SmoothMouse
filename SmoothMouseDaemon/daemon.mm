#import "daemon.h"

#import <IOKit/IODataQueueClient.h>
#import <IOKit/kext/KextManager.h>
#import <mach/mach.h>
#include <pthread.h>

#import "driver.h"
#import "kextdaemon.h"
#import "constants.h"
#import "debug.h"
#import "mouse.h"
#import "accel.h"
#import "prio.h"

#define KEXT_CONNECT_RETRIES (3)
#define SUPERVISOR_SLEEP_TIME_USEC (500000)

BOOL is_debug = 0;
BOOL is_memory = 0;
BOOL is_timings = 0;
BOOL is_dumping = 0;
BOOL mouse_enabled;
BOOL trackpad_enabled;

double velocity_mouse;
double velocity_trackpad;
AccelerationCurve curve_mouse;
AccelerationCurve curve_trackpad;
Driver driver;

double start, end, e1, e2, mhs, mhe, outerstart, outerend, outersum = 0, outernum = 0;
NSMutableArray* logs = [[NSMutableArray alloc] init];

MouseSupervisor *sMouseSupervisor;

Daemon *sDaemonInstance = NULL;

static void *HandleKernelEventThread(void *instance);

void trap_signals(int sig)
{
    NSLog(@"trapped signal: %d", sig);
    [sDaemonInstance release];
    if (is_debug) {
        debug_end();
    }
    restoreSystemMouseSettings();
    exit(-1);
}

const char *get_driver_string(int mouse_driver) {
    switch (mouse_driver) {
        case DRIVER_QUARTZ_OLD: return "QUARTZ_OLD";
        case DRIVER_QUARTZ: return "QUARTZ";
        case DRIVER_IOHID: return "IOHID";
        default: return "?";
    }
}

const char *get_acceleration_string(AccelerationCurve curve) {
    switch (curve) {
        case ACCELERATION_CURVE_LINEAR: return "LINEAR";
        case ACCELERATION_CURVE_WINDOWS: return "WINDOWS";
        case ACCELERATION_CURVE_OSX: return "OSX";
        default: return "?";
    }
}

@implementation Daemon

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

#if 0
    for (int i = 0; i != 31; ++i) {
        signal(i, trap_signals);
    }
#endif

    signal(SIGINT, trap_signals);
    signal(SIGKILL, trap_signals);
    signal(SIGTERM, trap_signals);

    sMouseSupervisor = [[MouseSupervisor alloc] init];

    NSLog(@"Mouse enabled: %d Mouse velocity: %f Mouse curve: %s",
          mouse_enabled,
          velocity_mouse,
          get_acceleration_string(curve_mouse));

    NSLog(@"Trackpad enabled: %d Trackpad velocity: %f Trackpad curve: %s",
          trackpad_enabled,
          velocity_trackpad,
          get_acceleration_string(curve_trackpad));

    NSLog(@"Driver: %s (%d)", get_driver_string(driver), driver);

	return self;
}

-(AccelerationCurve) getAccelerationCurveFromDict:(NSDictionary *)dictionary withKey:(NSString *)key {
    NSString *value;
    value = [dictionary valueForKey:key];
	if (value) {
        if ([value compare:@"Windows"] == NSOrderedSame) {
            return ACCELERATION_CURVE_WINDOWS;
        }
        if ([value compare:@"OS X"] == NSOrderedSame) {
            return ACCELERATION_CURVE_OSX;
        }
	}
    return ACCELERATION_CURVE_LINEAR;
}

-(BOOL) loadSettings
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PREFERENCES_FILENAME];
	NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:file];

	if (!dict) {
		NSLog(@"cannot open file %@", file);
        return NO;
	}

    NSLog(@"found %@", file);

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

    value = [dict valueForKey:SETTINGS_DRIVER];
	if (value) {
		driver = (Driver) [value intValue];
	} else {
		driver = (Driver) SETTINGS_DRIVER_DEFAULT;
	}

    curve_mouse = [self getAccelerationCurveFromDict:dict withKey:SETTINGS_MOUSE_ACCELERATION_CURVE];
    curve_trackpad = [self getAccelerationCurveFromDict:dict withKey:SETTINGS_TRACKPAD_ACCELERATION_CURVE];

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

        service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("com_cyberic_SmoothMouse"));
        if (service == IO_OBJECT_NULL) {
            NSLog(@"IOServiceGetMatchingService() failed");
            goto error;
        }

        error = IOServiceOpen(service, mach_task_self(), 0, &connect);
        if (error) {
            NSLog(@"IOServiceOpen() failed (kext is busy)");
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
        dataSize = (uint32_t) size;

        BOOL ok = [self configureDriver];
        if (!ok) {
            NSLog(@"Failed to configure driver");
            goto error;
        }

        int threadError = pthread_create(&mouseEventThreadID, NULL, &HandleKernelEventThread, self);
        if (threadError != 0)
        {
            NSLog(@"Failed to start mouse event thread");
            goto error;
        }

        initializeSystemMouseSettings();

        [self hookGlobalMouseEvents];

        connected = YES;
    }

	return YES;

error:
    return NO;
}

-(BOOL) hookGlobalMouseEvents
{
    [NSEvent setMouseCoalescingEnabled:FALSE];
    globalMouseMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:(NSMouseMovedMask | NSLeftMouseDraggedMask | NSRightMouseDraggedMask | NSOtherMouseDraggedMask)
                                           handler:^(NSEvent *event) {
                                               [self handleGlobalMouseMovedEvent:event];
                                           }];

    NSLog(@"Registered global mouse event listener");

    return YES;
}

-(BOOL) unhookGlobalMouseEvents
{
    [NSEvent removeMonitor:globalMouseMonitor];

    NSLog(@"Unregistered global mouse event listener");

    return YES;
}

-(void) handleGlobalMouseMovedEvent:(NSEvent *) event
{
    BOOL match = [sMouseSupervisor popMouseEvent:(int) [event deltaX]: (int) [event deltaY]];
    if (!match) {
        mouse_refresh();
        if (is_debug) {
            NSLog(@"Another application altered mouse location");
        }
    } else {
        //NSLog(@"MATCH: %d, queue size: %d, delta x: %f, delta y: %f",
        //      match,
        //      [sMouseSupervisor numItems],
        //      [event deltaX],
        //      [event deltaY]
        //      );
    }
}

-(BOOL) configureDriver
{
    kern_return_t	kernResult;

    uint64_t scalarI_64[1];

    uint32_t configuration = 0;

    if (mouse_enabled) {
        configuration |= KEXT_CONF_MOUSE_ENABLED;
    }

    if (trackpad_enabled) {
        configuration |= KEXT_CONF_TRACKPAD_ENABLED;
    }

    if (driver == DRIVER_QUARTZ_OLD) {
        configuration |= KEXT_CONF_QUARTZ_OLD; // set compatibility mode in kernel
    }

    scalarI_64[0] = configuration;

    kernResult = IOConnectCallScalarMethod(connect,
                                           kConfigureMethod,
                                           scalarI_64,
                                           1,
                                           NULL,
                                           NULL);

    if (kernResult == KERN_SUCCESS) {
        return YES;
    } else {
        return NO;
    }
}

-(BOOL) disconnectFromDriver
{
    if (connected) {
        if (recvPort) {
            mach_port_destroy(mach_task_self(), recvPort);
        }

        int rv = pthread_join(mouseEventThreadID, NULL);
        if (rv != 0) {
            NSLog(@"Failed to wait for mouse event thread");
        }

        if (address) {
            IOConnectUnmapMemory(connect, kIODefaultMemoryType, mach_task_self(), address);
        }

        if (connect) {
            IOServiceClose(connect);
        }

        [self unhookGlobalMouseEvents];

        connected = NO;

        NSLog(@"Disconnected from driver");
    }

    return YES;
}

-(oneway void) release
{
    [self disconnectFromDriver];
	[super release];
}

static void *HandleKernelEventThread(void *instance)
{
    Daemon *self = (Daemon *) instance;

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    kern_return_t error;

	char *buf = (char *)malloc(self->dataSize);
	if (!buf) {
		NSLog(@"malloc error");
		return NULL;
	}

    [Prio setRealtimePrio];

    (void) mouse_init();

    static int counter = 0;
    while (IODataQueueWaitForAvailableData(self->queueMappedMemory, self->recvPort) == kIOReturnSuccess) {
        outerend = GET_TIME();
        int numPackets = 0;
        while (IODataQueueDataAvailable(self->queueMappedMemory)) {
            start = GET_TIME();
            numPackets++;
            counter++;
            error = IODataQueueDequeue(self->queueMappedMemory, buf, &(self->dataSize));
            mouse_event_t *mouse_event = (mouse_event_t *) buf;
            if (!error) {
                mhs = GET_TIME();
                mouse_handle(mouse_event);
                mhe = GET_TIME();
            } else {
                LOG(@"IODataQueueDequeue() failed");
                exit(0);
            }
            end = GET_TIME();
            if (is_timings) {
                LOG(@"outer: %f, inner: %f, post event: %f, (mouse_handle): %f, seqnum: %llu, data entries handled: %d, coalesced: %d", outerend-outerstart, end-start, e2-e1, mhe-mhs, mouse_event->seqnum, numPackets, numCoalescedEvents);
            }
        }

        if (outerstart != 0 && outerend != 0) {
            outernum += 1;
            outersum += (outerend-outerstart);
        }

        outerstart = GET_TIME();
    }

    (void) mouse_cleanup();

	free(buf);

    [pool drain];

    return NULL;
}

-(void) mainLoop
{
    int retries_left = KEXT_CONNECT_RETRIES;
    while(1) {
        BOOL active = [self isActive];
        if (active) {
            BOOL ok = [self connectToDriver];
            if (!ok) {
                NSLog(@"Failed to connect to kext (retries_left = %d)", retries_left);
                if (retries_left < 1) {
                    exit(-1);
                }
                retries_left--;
            } else {
                retries_left = KEXT_CONNECT_RETRIES;
                initializeSystemMouseSettings();
                mouse_update_clicktime();
            }
        } else {
            [self disconnectFromDriver];
        }
        usleep(SUPERVISOR_SLEEP_TIME_USEC);
    }
}

-(BOOL) isActive {
    BOOL active = NO;
    CFDictionaryRef sessionDict = CGSessionCopyCurrentDictionary();
    if (sessionDict) {
        const void *loggedIn = CFDictionaryGetValue(sessionDict, kCGSessionOnConsoleKey);
        CFRelease(sessionDict);
        if (loggedIn != kCFBooleanTrue) {
            active = NO;
        } else {
            active = YES;
        }
    }
    return active;
}

@end
