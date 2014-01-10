
#import <Cocoa/Cocoa.h>

#import "Configuration.h"
#import "Kext.h"
#import "DaemonController.h"
#import "Metadata.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, NSTableViewDelegate, NSTableViewDataSource, Metadata> {
@private
    Kext *kext;
    Configuration *configuration;
    DaemonController *daemonController;
    Metadata *metadata;
    IBOutlet NSTableView *_tableView;
    IBOutlet NSButton *checkboxEnable;
    IBOutlet NSPopUpButton *curvePopup;
    IBOutlet NSSlider *velocitySlider;
    IBOutlet NSBox *deviceView;
}

@property (assign) IBOutlet NSWindow *window;
- (IBAction)enableToggled:(id)sender;
- (IBAction)curveChanged:(id)sender;
- (IBAction)velocityChanged:(id)sender;
- (IBAction)deviceSelected:(id)sender;

@end
