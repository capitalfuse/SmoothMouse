#import <Cocoa/Cocoa.h>
#import "daemon.h"

@interface AppDelegate : NSObject <NSApplicationDelegate> {
    int argc;
    char **argv;
}

- (id)initWithArgc:(int)argc_ andArgv:(char **)argv_;

@end
