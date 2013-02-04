#import <Cocoa/Cocoa.h>
#import "daemon.h"

@interface AppDelegate : NSObject <NSApplicationDelegate> {
    int argc;
    char **argv;
    Daemon *daemon;
}

- (id)initWithArgc:(int)argc_ andArgv:(char **)argv_;

@end
