#import "AppDelegate.h"

#import <Sparkle/Sparkle.h>

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
    NSString *bundlePath = @"/Library/PreferencePanes/SmoothMouse.prefPane";
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];

    if (bundle == nil) {
        NSString *errorMessage = [NSString stringWithFormat:@"Could not find bundle: '%@'", bundlePath];
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:errorMessage];
        [alert runModal];
        return;
    }

    BOOL foreground = NO;
    for(int i = 0; i < argc; i++) {
        NSLog(@"%d: %s", i, argv[i]);
        if (strcmp("--foreground", argv[i]) == 0) {
            //NSLog(@"foreground!");
            foreground = YES;
        }
    }
    
    sparkleUpdater = [SUUpdater updaterForBundle:bundle];
    [sparkleUpdater setDelegate:self];
    
    if (foreground) {
        [sparkleUpdater checkForUpdates:self];
    } else {
        [sparkleUpdater checkForUpdatesInBackground];
    }
    
    [self isDone];
}

-(void) isDone {
    BOOL isDone = ![sparkleUpdater updateInProgress];
    //NSLog(@"isDone? %d", isDone);
    [self performSelector:@selector(isDone) withObject:self afterDelay:1];
    if (isDone) {
        [NSApp terminate:nil];
    }
}

#if 0
-(void)updateAlert:(id)sender finishedWithChoice:(id) choice {
    NSLog(@"finishedWithChoice");
}

- (void)updaterDidNotFindUpdate:(SUUpdater *)update {
    NSLog(@"updaterDidNotFindUpdate");
}

- (void)updater:(SUUpdater *)updater didFinishLoadingAppcast:(SUAppcast *)appcast {
    NSLog(@"didFinishLoadingAppcast");
}

- (void)updater:(SUUpdater *)updater willInstallUpdate:(SUAppcastItem *)update {
    NSLog(@"willInstallUpdate");
}

- (void)updaterWillRelaunchApplication:(SUUpdater *)updater {
    NSLog(@"updaterWillRelaunchApplication");
}
#endif

@end
