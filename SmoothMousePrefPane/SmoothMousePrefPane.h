#import <PreferencePanes/PreferencePanes.h>
#import <AppKit/NSTextView.h>
#import <Cocoa/Cocoa.h>

@interface SmoothMousePrefPane : NSPreferencePane <NSTextFieldDelegate> {
@private
    IBOutlet NSMenu         *buttonMenu;
    
    IBOutlet NSButton       *enableForMouse;
    IBOutlet NSPopUpButton  *accelerationCurveMouse;
	IBOutlet NSSlider		*velocityForMouse;
    
    IBOutlet NSButton       *enableForTrackpad;
    IBOutlet NSPopUpButton  *accelerationCurveTrackpad;
	IBOutlet NSSlider		*velocityForTrackpad;

    IBOutlet NSButton       *checkForUpdates;
    IBOutlet NSButton       *automaticallyCheckForUpdates;
    IBOutlet NSButton       *reportBug;
    IBOutlet NSButton       *uninstallButton;

    IBOutlet NSTextField    *bundleVersion;
    IBOutlet NSTextField    *urlLabel;
    
    IBOutlet NSTextView     *credits;
}

- (void)mainViewDidLoad;

-(IBAction)pressCheckForUpdates:(id) sender;
-(IBAction)pressEnableDisableAutomaticallyCheckForUpdates:(id) sender;
-(IBAction)pressReportBug:(id) sender;
-(IBAction)pressUninstall:(id) sender;  

-(void)createLaunchAgentsDirectory;
-(BOOL)launchExecutable:(NSString*)executable withArguments:(NSArray *)arguments;

-(BOOL) settingsFileExists;
-(void) saveDefaultSettingsFile;

- (IBAction)changeVelocity:(id) sender;
- (IBAction)changeAccelerationCurve:(id) sender;
- (IBAction)pressEnableDisableMouse:(id) sender;
- (IBAction)pressEnableDisableTrackpad:(id) sender;

- (void)startOrStopDaemon;
- (BOOL)isDaemonRunning;
- (BOOL)startDaemon;
- (BOOL)stopDaemon;

- (BOOL)isStartAtLoginEnabled;
- (BOOL)isAutomaticallyCheckForUpdatesEnabled;

- (BOOL)enableStartAtLogin:(BOOL) enable;
- (BOOL)enableAutomaticallyCheckForUpdates:(BOOL) enable;

- (double)getVelocityForMouse;
- (double)getVelocityForTrackpad;
- (BOOL)getMouseEnabled;
- (BOOL)getTrackpadEnabled;
- (NSString *)getAccelerationCurveForMouse;
- (NSString *)getAccelerationCurveForTrackpad;
- (BOOL)saveVelocityForMouse:(double) valueMouse andTrackpad:(double) valueTrackpad;
- (BOOL)saveMouseEnabled:(BOOL) value;
- (BOOL)saveTrackpadEnabled:(BOOL) value;
- (BOOL)saveAccelerationCurveForMouse:(NSString *) value;
- (BOOL)saveAccelerationCurveForTrackpad:(NSString *) value;

- (void)restartDaemonIfRunning;
@end

