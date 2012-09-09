#import <PreferencePanes/PreferencePanes.h>
#import <AppKit/NSTextView.h>
#import <Cocoa/Cocoa.h>

@interface SmoothMousePrefPane : NSPreferencePane {
@private
	IBOutlet NSButton		*switchOnOff;
	IBOutlet NSButton		*startAtLogin;
	IBOutlet NSTextField	*status;
	IBOutlet NSSlider		*velocity;
}

- (void)mainViewDidLoad;

- (IBAction)pressSwitchOnOff:(id) sender;
- (IBAction)pressStartAtLogin:(id) sender;
- (IBAction)changeVelocity:(id) sender;

- (BOOL)daemonRunning;
- (BOOL)startDaemon;
- (BOOL)stopDaemon;

- (BOOL)startAtLoginEnabled;
- (BOOL)putLaunchdPlist;
- (BOOL)deleteLaunchdPlist;

- (double)velocity;
- (BOOL)saveVelocity:(double) value;

@end

