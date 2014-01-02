
#import <Cocoa/Cocoa.h>

#import "Configuration.h"
#import "Kext.h"

@interface AppDelegate : NSObject <NSApplicationDelegate> {
@private
    Kext *kext;
    Configuration *configuration;
}

@property (assign) IBOutlet NSWindow *window;

@end
