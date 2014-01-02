#import "Daemon.h"

// for hooking foreground app switch
#include <Carbon/Carbon.h>
#include <CoreServices/CoreServices.h>

#import "debug.h"
#import "DriverEventLog.h"
#import "Prio.h"

#import "mouse.h"
#import "keyboard.h"

#define KEXT_CONNECT_RETRIES (3)
#define SUPERVISOR_SLEEP_TIME_USEC (500000)

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

@implementation Daemon

/* === KEXTPROTOCOL === */
- (void)connected {
}

- (void)disconnected {
    (void) mouse_cleanup();
}

- (void)threadStarted {
    [Prio setRealtimePrio: @"KernelEventThread" withComputation:20000 withConstraint:50000];
    (void) mouse_init();
}

- (void)didReceiveEvent:(kext_event_t *)kext_event {
    Config *config = [Config instance];
    //LOG(@"kext event: size %u, event type: %u, device_type: %d, timestamp: %llu", self->queueSize, kext_event->base.event_type, kext_event->base.device_type, kext_event->base.timestamp);

    switch (kext_event->base.event_type) {
        case EVENT_TYPE_DEVICE_ADDED:
        {
            device_added_event_t *device_added = &kext_event->device_added;
            device_information_t kextDeviceInfo;
            [kext kextMethodGetDeviceInformation: &kextDeviceInfo forDeviceWithDeviceType:device_added->base.device_type andVendorId: device_added->base.vendor_id andProductID: device_added->base.product_id];
            if (device_added->base.device_type == DEVICE_TYPE_POINTING) {
                DeviceInfo *deviceInfo = [config getDeviceWithDeviceType: DEVICE_TYPE_POINTING andVendorID:device_added->base.vendor_id andProductID:device_added->base.product_id];
                if (deviceInfo != NULL) {
                    device_configuration_t device_config;
                    memset(&device_config, 0, sizeof(device_configuration_t));
                    device_config.device_type = DEVICE_TYPE_POINTING;
                    device_config.vendor_id = device_added->base.vendor_id;
                    device_config.product_id = device_added->base.product_id;
                    device_config.enabled = 1;
                    [kext kextMethodConfigureDevice:&device_config];
                    LOG(@"Enabled POINTING device (trackpad: %d): VendorID: %u, ProductID: %u, Manufacturer: '%s', Product: '%s'", kextDeviceInfo.pointing.is_trackpad, kextDeviceInfo.vendor_id, kextDeviceInfo.product_id, kextDeviceInfo.manufacturer_string, kextDeviceInfo.product_string);
                    if (kextDeviceInfo.pointing.is_trackpad) {
                        [config setTrackpadEnabled: YES];
                    } else {
                        [config setMouseEnabled: YES];
                    }
                } else {
                    LOG(@"Ignored POINTING device (trackpad: %d): VendorID: %u, ProductID: %u, Manufacturer: '%s', Product: '%s'", kextDeviceInfo.pointing.is_trackpad, kextDeviceInfo.vendor_id, kextDeviceInfo.product_id, kextDeviceInfo.manufacturer_string, kextDeviceInfo.product_string);                        }
            } else if (device_added->base.device_type == DEVICE_TYPE_KEYBOARD) {
                if ([config keyboardEnabled]) {
                    device_configuration_t device_config;
                    memset(&device_config, 0, sizeof(device_configuration_t));
                    device_config.device_type = DEVICE_TYPE_KEYBOARD;
                    device_config.vendor_id = device_added->base.vendor_id;
                    device_config.product_id = device_added->base.product_id;
                    [config getKeyboardConfiguration: &device_config.keyboard.enabledKeys[0]];
                    device_config.enabled = 1;
                    [kext kextMethodConfigureDevice:&device_config];
                    LOG(@"ENABLED KEYBOARD DEVICE (trackpad: %d), vendor_id: %u, product_id: %u", kextDeviceInfo.pointing.is_trackpad, kextDeviceInfo.vendor_id, kextDeviceInfo.product_id);
                }
            }
            break;
        }
        case EVENT_TYPE_DEVICE_REMOVED:
        {
            device_removed_event_t *device_removed = &kext_event->device_removed;
            LOG(@"DEVICE REMOVED, VendorID: %u, ProductID: %u",
                device_removed->base.vendor_id, device_removed->base.product_id);
            break;
        }
        case EVENT_TYPE_POINTING:
            //LOG(@"EVENT_TYPE_POINTING");
            mouse_process_kext_event(&kext_event->pointing);
            break;
        case EVENT_TYPE_KEYBOARD:
            //LOG(@"EVENT_TYPE_KEYBOARD");
            keyboard_process_kext_event(&kext_event->keyboard);
            break;
        default:
            LOG(@"Unknown event type: %d", kext_event->base.event_type);
            break;
    }
    if ([config debugEnabled]) {
        debug_register_event(kext_event);
    }
}

/* ===              === */

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

    kext = [[Kext alloc] init];
    [kext setDelegate:self];

    globalMouseMonitor = NULL;
    runLoop = [NSRunLoop currentRunLoop];

    Config *config = [Config instance];

    if (![config debugEnabled]) {
        if ([config getNumberOfDevices] < 1) {
            NSLog(@"No devices enabled");
            [self dealloc];
            return nil;
        }
    }

    accel = [[SystemMouseAcceleration alloc] init];
    sMouseSupervisor = [[MouseSupervisor alloc] init];
    sDriverEventLog = [[DriverEventLog alloc] init];

    if ([config keyboardEnabled]) {
        NSLog(@"Keyboard enabled: %d", [config keyboardEnabled]);
    }

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

    if (err) {
        NSLog(@"Could not install event handler");
    }
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

-(void) destroy
{
    [kext disconnect];
    [accel restore];
}

-(BOOL) connectKext
{
    BOOL ok = YES;

    if (!terminating_smoothmouse) {
        ok = [kext connect];

        [accel reset];

        if ([[Config instance] latencyEnabled]) {
            [interruptListener start];
        }
    }

    return ok;
}

-(BOOL) disconnectKext
{
    BOOL ok = [kext disconnect];

    if ([[Config instance] latencyEnabled]) {
        [interruptListener stop];
    }

    [mouseEventListener stop:runLoop];

    return ok;
}

-(void) mainLoop
{
    startTime = time(NULL);
    int retries_left = KEXT_CONNECT_RETRIES;
    while(1) {
        BOOL active = [self isActive];
        if (active) {
            BOOL ok = [self connectKext];
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
            [self disconnectKext];
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
    NSLog(@"Connected: %d", [kext isConnected]);
    NSLog(@"Mouse enabled: %d", [[Config instance] mouseEnabled]);
    NSLog(@"Trackpad enabled: %d", [[Config instance] trackpadEnabled]);
    NSLog(@"Keyboard enabled: %d", [[Config instance] keyboardEnabled]);
    NSLog(@"Kernel events since start: %llu", [kext numEvents]);
    NSLog(@"Number of lost kext events: %d", totalNumberOfLostEvents);
    NSLog(@"Number of lost clicks: %d", [sMouseSupervisor numClickEvents]);
    NSLog(@"===");
}

@end
