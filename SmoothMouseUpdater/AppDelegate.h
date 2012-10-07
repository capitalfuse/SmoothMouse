#import <Cocoa/Cocoa.h>
#import <Sparkle/Sparkle.h>

@interface AppDelegate : NSObject <NSApplicationDelegate> {
    int argc;
    char **argv;
    SUUpdater *sparkleUpdater;
}

- (id)initWithArgc:(int)argc_ andArgv:(char **)argv_;
- (void)updaterDidNotFindUpdate:(SUUpdater *)update;
- (void)updater:(SUUpdater *)updater willInstallUpdate:(SUAppcastItem *)update;
- (void)isDone;

@end
