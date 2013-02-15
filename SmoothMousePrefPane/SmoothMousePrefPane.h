#import <PreferencePanes/PreferencePanes.h>
#import <AppKit/NSTextView.h>
#import <Cocoa/Cocoa.h>

@interface SmoothMousePrefPane : NSPreferencePane <NSTextFieldDelegate> {
@private
    IBOutlet NSTabView      *tabView;
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

-(void)toggleVersionString;
-(void)writeStringToClipboard:(NSString *)string;

- (void)tabView:(NSTabView *)tv didSelectTabViewItem:(NSTabViewItem *)tvi;

-(IBAction)pressCheckForUpdates:(id) sender;
-(IBAction)pressEnableDisableAutomaticallyCheckForUpdates:(id) sender;
-(IBAction)pressReportBug:(id) sender;
-(IBAction)pressUninstall:(id) sender;  

-(NSString *)findLocationOfPrefPane;
-(NSString *)findLocationOfPrefPaneFile:(NSString *)file;
-(void)createLaunchAgentsDirectory;
-(BOOL)launchExecutable:(NSString*)executable withArguments:(NSArray *)arguments;
-(BOOL)launchScriptWithSudoRights:(NSString *) script withKeepPreferences:(BOOL)keepPreferences;

-(BOOL)settingsFileExists;
-(void)saveDefaultSettingsFile;

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
- (NSInteger)getAccelerationCurveForMouse;
- (NSInteger)getAccelerationCurveForTrackpad;
- (NSInteger)getAccelerationCurveForKey: (NSString *) key;
- (BOOL)saveVelocityForMouse:(double) valueMouse andTrackpad:(double) valueTrackpad;
- (BOOL)saveMouseEnabled:(BOOL) value;
- (BOOL)saveTrackpadEnabled:(BOOL) value;
- (BOOL)saveAccelerationCurveForMouse:(NSString *) value;
- (BOOL)saveAccelerationCurveForTrackpad:(NSString *) value;
- (NSInteger)getIndexFromAccelerationCurveString: (NSString *) s;

- (void)restartDaemonIfRunning;
@end

