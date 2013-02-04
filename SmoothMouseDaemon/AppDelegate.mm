#import "AppDelegate.h"
#import "daemon.h"
#import "debug.h"
#import "accel.h"

@implementation AppDelegate

-(id)initWithArgc:(int)argc_ andArgv:(char **)argv_
{
    if (self = [super init])
    {
        argc = argc_;
        argv = argv_;
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    for(int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--debug") == 0) {
            is_debug = 1;
            NSLog(@"Debug mode enabled");
        }

        if (strcmp(argv[i], "--memory") == 0) {
            is_memory = 1;
            NSLog(@"Memory logging enabled");
        }

        if (strcmp(argv[i], "--timings") == 0) {
            is_timings = 1;
            NSLog(@"Timing logging enabled");
        }
    }

	daemon = [[Daemon alloc] init];
    if (daemon == NULL) {
        NSLog(@"Daemon failed to initialize. BYE.");
        exit(-1);
    }
    sDaemonInstance = daemon;

    [NSThread detachNewThreadSelector:@selector(mainLoop) toTarget:daemon withObject:0];
}

@end
