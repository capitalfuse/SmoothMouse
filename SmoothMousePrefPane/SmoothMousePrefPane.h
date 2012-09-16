#import <PreferencePanes/PreferencePanes.h>
#import <AppKit/NSTextView.h>
#import <Cocoa/Cocoa.h>

@interface SmoothMousePrefPane : NSPreferencePane {
@private
	IBOutlet NSButton		*switchOnOff;
	IBOutlet NSButton		*startAtLogin;
	IBOutlet NSTextField	*status;
	IBOutlet NSSlider		*velocity;
    IBOutlet NSButton       *enableForMouse;
    IBOutlet NSButton       *enableForTrackpad;
}

- (void)mainViewDidLoad;

- (IBAction)pressSwitchOnOff:(id) sender;
- (IBAction)pressStartAtLogin:(id) sender;
- (IBAction)changeVelocity:(id) sender;
- (IBAction)pressEnableDisableMouse:(id) sender;
- (IBAction)pressEnableDisableTrackpad:(id) sender;

- (BOOL)daemonRunning;
- (BOOL)startDaemon;
- (BOOL)stopDaemon;

- (BOOL)startAtLoginEnabled;
- (BOOL)putLaunchdPlist;
- (BOOL)deleteLaunchdPlist;

- (double)velocity;
- (BOOL)isMouseEnabled;
- (BOOL)isTrackpadEnabled;
- (BOOL)saveVelocity:(double) value;
- (BOOL)saveMouseEnabled:(BOOL) value;
- (BOOL)saveTrackpadEnabled:(BOOL) value;

@end

