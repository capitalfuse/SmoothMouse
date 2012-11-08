#import <IOKit/IODataQueueClient.h>
#import <IOKit/kext/KextManager.h>
#import <mach/mach.h>
#include <pthread.h>

#import "kextdaemon.h"
#import "constants.h"
#import "debug.h"
#import "mouse.h"
#import "accel.h"

BOOL is_debug;
BOOL is_event = 0;

static BOOL mouse_enabled;
static BOOL trackpad_enabled;
static double velocity_mouse;
static double velocity_trackpad;

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
	mach_vm_address_t address;
    mach_vm_size_t size;
}

-(id)init;
-(oneway void) release;

-(BOOL) loadSettings;
-(BOOL) loadDriver;
-(BOOL) connectToDriver;
-(BOOL) configureDriver;
-(BOOL) disconnectFromDriver;
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
    
	return self;
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
		is_event = 1;
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
        dataSize = (uint32_t) size;

        [self configureDriver];

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

    if (!is_event) {
        configuration |= 1 << 2;
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
    
    (void) mouse_init();
    
    while (IODataQueueWaitForAvailableData(self->queueMappedMemory, self->recvPort) == kIOReturnSuccess) {
        
        pthread_mutex_lock(&mutex);

        if (self->connected) {

            while (IODataQueueDataAvailable(self->queueMappedMemory)) {
                error = IODataQueueDequeue(self->queueMappedMemory, buf, &(self->dataSize));
                if (!error) {
                    mouse_event_t *mouse_event = (mouse_event_t *) buf;
                    double velocity;
                    switch (mouse_event->device_type) {
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
                    mouse_handle(mouse_event, velocity);
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
        BOOL active = [self isActive];
        if (active) {
            BOOL ok = [self connectToDriver];
            if (!ok) {
                NSLog(@"Failed to connect to kext");
                exit(-1);
            }
            initializeSystemMouseSettings(mouse_enabled, trackpad_enabled);
        } else {
            [self disconnectFromDriver];
        }
        sleep(2);
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
    exit(-1);
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
