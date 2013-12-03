#import "daemon.h"

#import <IOKit/IODataQueueClient.h>
#import <IOKit/kext/KextManager.h>
#import <mach/mach.h>
#include <pthread.h>

// for hooking foreground app switch
#include <Carbon/Carbon.h>
#include <CoreServices/CoreServices.h>

#import "Daemon.h"
#import "driver.h"
#import "constants.h"
#import "debug.h"
#import "mouse.h"
#import "SystemMouseAcceleration.h"
#import "Prio.h"
#import "Config.h"
#import "OverlayWindow.h"
#import "InterruptListener.h"
#import "DriverEventLog.h"

#define KEXT_CONNECT_RETRIES (3)
#define SUPERVISOR_SLEEP_TIME_USEC (500000)

double start, end, e1, e2, mhs, mhe, outerstart, outerend, outersum = 0, outernum = 0;

static int terminating_smoothmouse = 0;

static void *KernelEventThread(void *instance);

void trap_signals(int sig)
{
    if (terminating_smoothmouse) {
        NSLog(@"already terminating");
        return;
    } else {
        terminating_smoothmouse = 1;
    }
    NSLog(@"trapped signal: %d", sig);
    [[Daemon instance] destroy];
    if ([[Config instance] debugEnabled]) {
        debug_end();
    }
    [NSApp terminate:nil];
}

void trap_sigusr(int sig) {
    [[Daemon instance] dumpState];
}

// more information about getting notified when fron app changes:
// http://stackoverflow.com/questions/763002/getting-notified-when-the-current-application-changes-in-cocoa
static OSStatus AppFrontSwitchedHandler(EventHandlerCallRef inHandlerCallRef, EventRef inEvent, void *inUserData)
{
    [(id)inUserData frontAppSwitched];
    return 0;
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

+(Daemon *) instance
{
    static Daemon* instance = nil;

    if (instance == nil) {
        instance = [[Daemon alloc] init];
    }

    return instance;
}

-(id)init
{
	self = [super init];

    connected = NO;
    globalMouseMonitor = NULL;
    eventsSinceStart = 0;
    runLoop = [NSRunLoop currentRunLoop];

    if (![[Config instance] debugEnabled]) {
        if (![[Config instance] mouseEnabled] && ![[Config instance] trackpadEnabled]) {
            NSLog(@"No devices enabled");
            [self dealloc];
            return nil;
        }
    }

    accel = [[SystemMouseAcceleration alloc] init];
    sMouseSupervisor = [[MouseSupervisor alloc] init];
    sDriverEventLog = [[DriverEventLog alloc] init];

    Config *config = [Config instance];

    NSLog(@"Mouse enabled: %d Mouse velocity: %f Mouse curve: %s",
          [config mouseEnabled],
          [config mouseVelocity],
          get_acceleration_string([config mouseCurve]));

    NSLog(@"Trackpad enabled: %d Trackpad velocity: %f Trackpad curve: %s",
          [config trackpadEnabled],
          [config trackpadVelocity],
          get_acceleration_string([config trackpadCurve]));

    NSLog(@"Driver: %s (%d)", driver_get_driver_string([config driver]), [config driver]);

    NSLog(@"Force refresh on drag enabled: %d", [config forceDragRefreshEnabled]);

    [self hookAppFrontChanged];

    if ([config overlayEnabled]) {
        overlay = [[OverlayWindow alloc] init];
    }

    if ([config latencyEnabled]) {
        interruptListener = [[InterruptListener alloc] init];
    }

    mouseEventListener = [[MouseEventListener alloc] init];

    return self;
}

-(void) trapSignals
{
#if 0
    for (int i = 0; i != 31; ++i) {
        signal(i, trap_signals);
    }
#endif

    signal(SIGINT, trap_signals);
    signal(SIGKILL, trap_signals);
    signal(SIGTERM, trap_signals);
    signal(SIGUSR1, trap_sigusr);
}

-(BOOL) loadDriver
{
	NSString *kextID = @"com.cyberic.smoothmouse";
	return (kOSReturnSuccess == KextManagerLoadKextWithIdentifier((CFStringRef)kextID, NULL));
}

-(BOOL) connectToDriver
{
    @synchronized(self) {
        if (!connected && !terminating_smoothmouse) {
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

            int threadError = pthread_create(&mouseEventThreadID, NULL, &KernelEventThread, self);
            if (threadError != 0)
            {
                NSLog(@"Failed to start mouse event thread");
                goto error;
            }

            [accel reset];

            if ([[Config instance] latencyEnabled]) {
                [interruptListener start];
            }

            connected = YES;
        }

        return YES;
error:
    return NO;
    }
}

-(void) redrawOverlay {
    [overlay redrawView];
}

-(void) say:(NSString *)message {
    NSTask *task;
    task = [[NSTask alloc] init];
    [task setLaunchPath: @"/usr/bin/say"];

    NSArray *arguments;
    arguments = [NSArray arrayWithObjects: message, nil];
    [task setArguments: arguments];

    NSPipe *pipe;
    pipe = [NSPipe pipe];
    [task setStandardOutput: pipe];

    [task launch];
    [task release];
}

- (void) hookAppFrontChanged
{
    EventTypeSpec spec = { kEventClassApplication,  kEventAppFrontSwitched };
    OSStatus err = InstallApplicationEventHandler(NewEventHandlerUPP(AppFrontSwitchedHandler), 1, &spec, (void*)self, NULL);

    if (err)
        NSLog(@"Could not install event handler");
}

- (void) frontAppSwitched {
    NSDictionary *activeApplicationDict = [[NSWorkspace sharedWorkspace] activeApplication];

    NSString *appId = [activeApplicationDict valueForKey:@"NSApplicationBundleIdentifier"];

    if (appId == nil) {
        NSRunningApplication *runningApp = [activeApplicationDict objectForKey:@"NSWorkspaceApplicationKey"];
        appId = [[runningApp executableURL] path];
    }

    if ([[Config instance] debugEnabled]) {
        LOG(@"Active App Id: %@", appId);
    }

    [[Config instance] setActiveAppId: appId];

    [self handleAppChanged];
}

-(void) handleAppChanged {
    if ([[Config instance] activeAppRequiresMouseEventListener]) {
        [sMouseSupervisor clearMoveEvents];
        [mouseEventListener start:runLoop];
    } else {
        [mouseEventListener stop:runLoop];
    }
}

-(BOOL) configureDriver
{
    kern_return_t	kernResult;

    uint64_t scalarI_64[1];

    uint32_t configuration = 0;

    Config *config = [Config instance];

    if ([config mouseEnabled]) {
        configuration |= KEXT_CONF_MOUSE_ENABLED;
    }

    if ([config trackpadEnabled]) {
        configuration |= KEXT_CONF_TRACKPAD_ENABLED;
    }

    if ([config driver] == DRIVER_QUARTZ_OLD) {
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

-(BOOL) disconnectFromKext
{
    @synchronized(self) {
        if (connected) {

            connected = NO;

            if (recvPort) {
                mach_port_destroy(mach_task_self(), recvPort);
            }

            int rv = pthread_join(mouseEventThreadID, NULL);
            if (rv != 0) {
                NSLog(@"Failed to wait for kernel event thread");
            }

            if (address) {
                IOConnectUnmapMemory(connect, kIODefaultMemoryType, mach_task_self(), address);
            }

            if (connect) {
                IOServiceClose(connect);
            }

            if ([[Config instance] latencyEnabled]) {
                [interruptListener stop];
            }

            [mouseEventListener stop:runLoop];
            
            NSLog(@"Disconnected from KEXT");
        }
        
        return YES;
    }
}

-(void) destroy
{
    [self disconnectFromKext];
    [accel restore];
}

static void *KernelEventThread(void *instance)
{
    Daemon *self = (Daemon *) instance;

    //NSLog(@"KernelEventThread: Start");

    kern_return_t error;

    char *buf = (char *)malloc(self->dataSize);
    if (!buf) {
        NSLog(@"malloc error");
        return NULL;
    }

    [Prio setRealtimePrio: @"KernelEventThread" withComputation:20000 withConstraint:50000];

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
            //LOG(@"Got event from kernel with timestamp: %llu", mouse_event->timestamp);
            if (!error) {
                mhs = GET_TIME();
                mouse_process_kext_event(mouse_event);
                self->eventsSinceStart++;
                mhe = GET_TIME();
            } else {
                LOG(@"IODataQueueDequeue() failed");
                exit(0);
            }
            end = GET_TIME();
            if ([[Config instance] timingsEnabled]) {
                LOG(@"timings: outer: %f, inner: %f, process mouse event: %f, seqnum: %llu, burst: %d, coalesced: %d", outerend-outerstart, end-start, mhe-mhs, mouse_event->seqnum, numPackets, numCoalescedEvents);
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

    //NSLog(@"KernelEventThread: End");

    return NULL;
}

-(void) mainLoop
{
    startTime = time(NULL);
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
                // TODO: refactor this (read: what a fucking mess this has become)
                if (!terminating_smoothmouse) {
                    [accel reset];
                    mouse_update_clicktime();
                }
            }
        } else {
            //NSLog(@"calling disconnectFromKext from mainloop");
            [self disconnectFromKext];
        }
        usleep(SUPERVISOR_SLEEP_TIME_USEC);
    }
}

-(BOOL) isActive {
    BOOL active = NO;
    // check if we are logged in
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
    // yes we are logged in, check if we want smoothmouse to be enabled in the current app
    if (active) {
        if ([[Config instance] activeAppIsExcluded]) {
            active = NO;
        }
    }
    return active;
}

-(BOOL) isMouseEventListenerActive {
    return [mouseEventListener isRunning];
}

-(void) dumpState {
    NSLog(@"=== DAEMON STATE ===");
    NSLog(@"Uptime seconds: %d", (int) (time(NULL) - startTime));
    NSLog(@"Connected: %d", connected);
    NSLog(@"Mouse enabled: %d", [[Config instance] mouseEnabled]);
    NSLog(@"Trackpad enabled: %d", [[Config instance] trackpadEnabled]);
    NSLog(@"Kernel events since start: %llu", eventsSinceStart);
    NSLog(@"Number of lost kext events: %d", totalNumberOfLostEvents);
    NSLog(@"Number of lost clicks: %d", [sMouseSupervisor numClickEvents]);
    NSLog(@"===");
}

@end
