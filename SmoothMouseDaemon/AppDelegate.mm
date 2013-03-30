#import "AppDelegate.h"
#import "Daemon.h"
#import "SystemMouseAcceleration.h"
#import "Config.h"

#import "debug.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    BOOL ok;

    Config *config = [Config instance];

    ok = [config parseCommandLineArguments];
    if (!ok) {
        NSLog(@"Failed parse command line arguments");
        exit(-1);
    }

    ok = [config readSettingsPlist];
    if (!ok) {
        NSLog(@"Failed to read settings .plist file (please open preference plane)");
        exit(-1);
    }

    Daemon *daemon = [Daemon instance];

    if (daemon == NULL) {
        NSLog(@"Daemon failed to initialize. BYE.");
        exit(-1);
    }

    [NSThread detachNewThreadSelector:@selector(mainLoop) toTarget:daemon withObject:0];
}

@end
