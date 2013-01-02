#import "SmoothMousePrefPane.h"
#import "constants.h"

#import <ServiceManagement/ServiceManagement.h>

// umask
#include <sys/types.h>
#include <sys/stat.h>

@implementation SmoothMousePrefPane

-(void)mainViewDidLoad
{
    if (![self settingsFileExists]) {
        [self saveDefaultSettingsFile];
        NSLog(@"Default settings saved");
        [self enableAutomaticallyCheckForUpdates:YES];
    }

    NSNumber *tabNumber = [[NSUserDefaults standardUserDefaults] objectForKey:KEY_SELECTED_TAB];
    if (tabNumber) {
        [tabView selectTabViewItemAtIndex:[tabNumber intValue]];
    }

    NSMenu *menuCopy;

    menuCopy = [buttonMenu copy];
    [accelerationCurveMouse setMenu: menuCopy];
    [menuCopy release];

    menuCopy = [buttonMenu copy];
    [accelerationCurveTrackpad setMenu: menuCopy];
    [menuCopy release];

    /* Mouse enabled state */
    if ([self getMouseEnabled]) {
        [enableForMouse setState:1];
    } else {
        [enableForMouse setState:0];
    }

    /* Trackpad enabled state */
    if ([self getTrackpadEnabled]) {
        [enableForTrackpad setState:1];
    } else {
        [enableForTrackpad setState:0];
    }

    /* Mouse acceleration curve */
    NSString *mouseAccelerationCurveString = [self getAccelerationCurveForMouse];
    if (mouseAccelerationCurveString) {
        [accelerationCurveMouse selectItemWithTitle:mouseAccelerationCurveString];
    }

    /* Trackpad acceleration curve */
    NSString *trackpadAccelerationCurveString = [self getAccelerationCurveForTrackpad];
    if (trackpadAccelerationCurveString) {
        [accelerationCurveTrackpad selectItemWithTitle:trackpadAccelerationCurveString];
    }

    /* Automatically check for updates */
    [automaticallyCheckForUpdates setState:[self isAutomaticallyCheckForUpdatesEnabled]];

	/* Velocity values */
	[velocityForMouse setDoubleValue:[self getVelocityForMouse]];
	[velocityForTrackpad setDoubleValue:[self getVelocityForTrackpad]];

    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *version = [[bundle infoDictionary] objectForKey:@"CFBundleVersion"];
    [bundleVersion setStringValue:version];

    NSString *filePath = [bundle pathForResource:@"Credits" ofType:@"rtf"];
    NSData *data = [NSData dataWithContentsOfFile:filePath];

    if (data) {
        NSDictionary *docAttributes;
        NSAttributedString *rtfString = [[NSAttributedString alloc] initWithRTF:data documentAttributes:&docAttributes];
        [[credits textStorage] setAttributedString: rtfString];
        [rtfString release];
    }
}

- (void)tabView:(NSTabView *)tv didSelectTabViewItem:(NSTabViewItem *)tvi {
    NSNumber *tabNumber = [NSNumber numberWithInteger: [tv indexOfTabViewItem:tvi]];
    [[NSUserDefaults standardUserDefaults] setObject:tabNumber forKey:KEY_SELECTED_TAB];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

-(void) labelWasClicked {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *url = [[bundle infoDictionary] objectForKey:@"SMHomepageURL"];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
}

-(IBAction)pressCheckForUpdates:(id) sender {
    NSArray *arguments;
    arguments = [NSArray arrayWithObjects:
                 @"/Library/PreferencePanes/SmoothMouse.prefPane/Contents/SmoothMouseUpdater.app",
                 @"--args",
                 @"--foreground",
                 nil];
    [self launchExecutable:@"/usr/bin/open" withArguments:arguments];
}

-(IBAction)pressEnableDisableAutomaticallyCheckForUpdates:(id) sender {
    BOOL checked = [automaticallyCheckForUpdates state];
    [self enableAutomaticallyCheckForUpdates:checked];
}

-(IBAction)pressReportBug:(id) sender {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *url = [[bundle infoDictionary] objectForKey:@"SMReportBugURL"];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
}

-(IBAction)pressUninstall:(id) sender {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Uninstall"];
    [alert setInformativeText:@"Are you sure you want to uninstall SmoothMouse"];
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert setShowsSuppressionButton:YES];
    [[alert suppressionButton] setTitle:@"Keep preferences"];
    NSInteger button = [alert runModal];
    BOOL keepPreferences = NO;
    if ([[alert suppressionButton] state] == NSOnState) {
        keepPreferences = YES;
    }
    [alert release];
    if (button == NSAlertFirstButtonReturn) {
        [self launchScriptWithSudoRights: [self findLocationOfPrefPaneFile:UNINSTALL_SCRIPT_FILENAME_BASE] withKeepPreferences:keepPreferences];
    }
}

-(BOOL)launchScriptWithSudoRights:(NSString *) script withKeepPreferences:(BOOL)keepPreferences
{
    BOOL                ret = NO;
    OSStatus            status;
    AuthorizationRef    authorizationRef;

    status = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment,
                                 kAuthorizationFlagDefaults, &authorizationRef);
    if (status != errAuthorizationSuccess) {
        goto cleanup;
    }

    AuthorizationItem right = {kAuthorizationRightExecute, 0, NULL, 0};
    AuthorizationRights rights = {1, &right};
    AuthorizationFlags flags = kAuthorizationFlagDefaults | kAuthorizationFlagInteractionAllowed | kAuthorizationFlagPreAuthorize | kAuthorizationFlagExtendRights;

    status = AuthorizationCopyRights(authorizationRef, &rights, NULL, flags, NULL);
    if (status != errAuthorizationSuccess) {
        goto cleanup;
    }

    const char *tool    = [script UTF8String];
    char *args[]        = { NULL, NULL };
    FILE *pipe          = NULL;

    if (keepPreferences) {
        args[0] = "-k";
    }

    status = AuthorizationExecuteWithPrivileges(authorizationRef, tool,
                                                kAuthorizationFlagDefaults, args, &pipe);
    if (status != errAuthorizationSuccess) {
        goto cleanup;
    }

    ret = YES;

cleanup:

    (void) AuthorizationFree(authorizationRef, kAuthorizationFlagDestroyRights);

    return ret;
}

-(BOOL)launchExecutable:(NSString*)executable withArguments:(NSArray *)arguments {
    NSTask *task;

    task = [[NSTask alloc] init];

    [task setLaunchPath: executable];
    [task setArguments: arguments];

    NSPipe *pipe;
    pipe = [NSPipe pipe];
    [task setStandardOutput: pipe];

    NSFileHandle *file;
    file = [pipe fileHandleForReading];

    [task launch];

    NSData *data;
    data = [file readDataToEndOfFile];

    NSString *string;
    string = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
    //NSLog (@"executable '%@' returned:\n%@", executable, string);

    [string release];
    [task release];

    return YES;
}

-(BOOL) settingsFileExists
{
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PREFERENCES_FILENAME];

	return [fm fileExistsAtPath:file];
}

-(void) saveDefaultSettingsFile
{
    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
                          [NSNumber numberWithDouble:SETTINGS_MOUSE_VELOCITY_DEFAULT], SETTINGS_MOUSE_VELOCITY,
                          [NSNumber numberWithDouble:SETTINGS_TRACKPAD_VELOCITY_DEFAULT], SETTINGS_TRACKPAD_VELOCITY,
                          [NSNumber numberWithBool:SETTINGS_MOUSE_ENABLED_DEFAULT], SETTINGS_MOUSE_ENABLED,
                          [NSNumber numberWithBool:SETTINGS_TRACKPAD_ENABLED_DEFAULT], SETTINGS_TRACKPAD_ENABLED,
                          SETTINGS_MOUSE_ACCELERATION_CURVE_DEFAULT, SETTINGS_MOUSE_ACCELERATION_CURVE,
                          SETTINGS_TRACKPAD_ACCELERATION_CURVE_DEFAULT, SETTINGS_TRACKPAD_ACCELERATION_CURVE,
                          nil];

    NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PREFERENCES_FILENAME];

    [dict writeToFile:file atomically:YES];
}

- (IBAction)changeVelocity:(id) sender
{
	[self saveVelocityForMouse:[velocityForMouse doubleValue] andTrackpad:[velocityForTrackpad doubleValue]];

    if ((sender == velocityForMouse && [self getMouseEnabled]) ||
        (sender == velocityForTrackpad && [self getTrackpadEnabled])) {
        [self restartDaemonIfRunning];
    }
}

- (IBAction)changeAccelerationCurve:(id) sender {
    NSPopUpButton *popupButton = sender;
    NSMenuItem *item = [popupButton selectedItem];
    NSString *title = [item title];
    if (popupButton == accelerationCurveMouse) {
        [self saveAccelerationCurveForMouse:title];
    } else {
        [self saveAccelerationCurveForTrackpad:title];
    }

    [self restartDaemonIfRunning];
}

- (IBAction)pressEnableDisableMouse:(id) sender
{
	[self saveMouseEnabled:[enableForMouse state]];
    [self startOrStopDaemon];
}

- (IBAction)pressEnableDisableTrackpad:(id) sender {
	[self saveTrackpadEnabled:[enableForTrackpad state]];
    [self startOrStopDaemon];
}

- (void) startOrStopDaemon {
    BOOL mouseOn = ([enableForMouse state] == 1);
    BOOL trackpadOn = ([enableForTrackpad state] == 1);
    if (mouseOn == YES || trackpadOn == YES) {
        if (![self enableStartAtLogin:YES]) {
            NSLog(@"Failed to enable start-at-login");
        }
        if ([self isDaemonRunning]) {
            [self stopDaemon];
        }
        [self startDaemon];

    } else {
        if ([self isDaemonRunning]) {
            [self stopDaemon];
        }
        if (![self enableStartAtLogin:NO]) {
            NSLog(@"Failed to enable start-at-login");
        }
    }
}

- (BOOL)isDaemonRunning
{
	CFDictionaryRef job;

	job = SMJobCopyDictionary(kSMDomainUserLaunchd, (CFStringRef)@"com.cyberic.smoothmouse");

	if (job) {
		CFRelease(job);
		return YES;
	} else {
		return NO;
	}
}

- (BOOL)startDaemon
{
    NSArray *arguments;
    NSString *plistFile = [NSHomeDirectory() stringByAppendingPathComponent: LAUNCH_AGENT_DAEMON_FILENAME];
    arguments = [NSArray arrayWithObjects: @"load", plistFile, nil];

    return [self launchExecutable: @"/bin/launchctl" withArguments:arguments];
}

- (BOOL)stopDaemon
{
    NSArray *arguments;
    NSString *plistFile = [NSHomeDirectory() stringByAppendingPathComponent: LAUNCH_AGENT_DAEMON_FILENAME];
    arguments = [NSArray arrayWithObjects: @"unload", plistFile, nil];

    return [self launchExecutable: @"/bin/launchctl" withArguments:arguments];
}

- (BOOL)isStartAtLoginEnabled
{
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: LAUNCH_AGENT_DAEMON_FILENAME];

	return [fm fileExistsAtPath:file];
}

- (BOOL)isAutomaticallyCheckForUpdatesEnabled
{
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: LAUNCH_AGENT_UPDATER_FILENAME];

	return [fm fileExistsAtPath:file];
}

-(NSString *)findLocationOfPrefPane {
	NSFileManager *fm = [NSFileManager defaultManager];
	if ([fm fileExistsAtPath:PREFERENCE_PANE_LOCATION_BASE]) {
        return PREFERENCE_PANE_LOCATION_BASE;
    }
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PREFERENCE_PANE_LOCATION_BASE];
	if ([fm fileExistsAtPath:file]) {
        return file;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Faulty installation"];
    [alert setInformativeText:@"Location of SmoothMouse preference pane was not found"];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
    [alert release];
    return NULL;
}

-(NSString *)findLocationOfPrefPaneFile:(NSString *)file {
    NSString *prefPaneLocation = [self findLocationOfPrefPane];
    NSString *completePath = [prefPaneLocation stringByAppendingString:file];
    return completePath;
}

-(void)createLaunchAgentsDirectory {
    mode_t oldMask = umask(S_IRWXO | S_IRWXG);

    NSFileManager *filemgr = [NSFileManager defaultManager];
    NSString *launchAgentsDirectory = [NSHomeDirectory() stringByAppendingPathComponent: @"/Library/LaunchAgents"];
    NSURL *newDir = [NSURL fileURLWithPath:launchAgentsDirectory];
    [filemgr createDirectoryAtURL: newDir withIntermediateDirectories:YES attributes: nil error:nil];

    (void) umask(oldMask);
}

- (BOOL)enableStartAtLogin:(BOOL) enable
{
    NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: LAUNCH_AGENT_DAEMON_FILENAME];
    if (enable) {
        [self createLaunchAgentsDirectory];
        NSMutableDictionary *dict = [[[NSMutableDictionary alloc] init] autorelease];
        [dict setObject:@"com.cyberic.smoothmouse" forKey:@"Label"];
        [dict setObject:[self findLocationOfPrefPaneFile:DAEMON_FILENAME_BASE] forKey:@"Program"];
        NSMutableDictionary *dict2 = [[[NSMutableDictionary alloc] init] autorelease];
        [dict2 setObject:[NSNumber numberWithBool:true] forKey:@"SuccessfulExit"];
        [dict setObject:dict2 forKey:@"KeepAlive"];
        return [dict writeToFile:file atomically:YES];
    } else {
        NSError *error;
        NSFileManager *fm = [NSFileManager defaultManager];

        return [fm removeItemAtPath:file error:&error];
    }
}

- (BOOL)enableAutomaticallyCheckForUpdates:(BOOL)enable
{
    NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: LAUNCH_AGENT_UPDATER_FILENAME];
    if (enable) {
        [self createLaunchAgentsDirectory];
        NSMutableDictionary *dict = [[[NSMutableDictionary alloc] init] autorelease];
        [dict setObject:@"com.cyberic.smoothmouseupdater" forKey:@"Label"];
        [dict setObject:[self findLocationOfPrefPaneFile:UPDATER_FILENAME_BASE] forKey:@"Program"];
        [dict setObject:[NSNumber numberWithBool:enable] forKey:@"RunAtLoad"];
        return [dict writeToFile:file atomically:YES];
    } else {
        NSError *error;
        NSFileManager *fm = [NSFileManager defaultManager];

        return [fm removeItemAtPath:file error:&error];
    }
}

- (double)getVelocityForMouse
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PREFERENCES_FILENAME];
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:file];
	NSNumber *value = [settings valueForKey:SETTINGS_MOUSE_VELOCITY];
	return value ? [value doubleValue] : SETTINGS_MOUSE_VELOCITY_DEFAULT;
}

- (double)getVelocityForTrackpad
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PREFERENCES_FILENAME];
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:file];
	NSNumber *value = [settings valueForKey:SETTINGS_TRACKPAD_VELOCITY];
	return value ? [value doubleValue] : SETTINGS_TRACKPAD_VELOCITY_DEFAULT;
}

- (BOOL)getMouseEnabled
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PREFERENCES_FILENAME];
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:file];
	NSNumber *value = [settings valueForKey:SETTINGS_MOUSE_ENABLED];
	return value ? [value boolValue] : FALSE;
}

- (BOOL)getTrackpadEnabled
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PREFERENCES_FILENAME];
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:file];
	NSNumber *value = [settings valueForKey:SETTINGS_TRACKPAD_ENABLED];
	return value ? [value boolValue] : FALSE;
}

- (NSString *)getAccelerationCurveForMouse {
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PREFERENCES_FILENAME];
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:file];
	NSString *value = [settings valueForKey:SETTINGS_MOUSE_ACCELERATION_CURVE];
	return value;
}

- (NSString *)getAccelerationCurveForTrackpad {
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PREFERENCES_FILENAME];
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:file];
	NSString *value = [settings valueForKey:SETTINGS_TRACKPAD_ACCELERATION_CURVE];
	return value;
}

- (BOOL)saveVelocityForMouse:(double) valueMouse andTrackpad:(double) valueTrackpad;
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PREFERENCES_FILENAME];
	NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:file];

    NSNumber *num;

    num = [NSNumber numberWithDouble:valueMouse];
	[settings setValue:num forKey:SETTINGS_MOUSE_VELOCITY];

    num = [NSNumber numberWithDouble:valueTrackpad];
	[settings setValue:num forKey:SETTINGS_TRACKPAD_VELOCITY];

	// TODO: does num need releasing here?
    return [settings writeToFile:file atomically:YES];
}

- (BOOL)saveAccelerationCurveForMouse:(NSString *) value {
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PREFERENCES_FILENAME];
	NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:file];
	[settings setValue:value forKey:SETTINGS_MOUSE_ACCELERATION_CURVE];
	return [settings writeToFile:file atomically:YES];
}

- (BOOL)saveAccelerationCurveForTrackpad:(NSString *) value {
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PREFERENCES_FILENAME];
	NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:file];
	[settings setValue:value forKey:SETTINGS_TRACKPAD_ACCELERATION_CURVE];
	return [settings writeToFile:file atomically:YES];
}

- (BOOL)saveMouseEnabled:(BOOL) value
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PREFERENCES_FILENAME];
	NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:file];
	NSNumber *num = [NSNumber numberWithBool:value];
	[settings setValue:num forKey:SETTINGS_MOUSE_ENABLED];
	return [settings writeToFile:file atomically:YES];
}

- (BOOL)saveTrackpadEnabled:(BOOL) value
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PREFERENCES_FILENAME];
	NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:file];
	NSNumber *num = [NSNumber numberWithBool:value];
	[settings setValue:num forKey:SETTINGS_TRACKPAD_ENABLED];
	return [settings writeToFile:file atomically:YES];
}

- (void)restartDaemonIfRunning {
	if ([self isDaemonRunning]) {
		[self stopDaemon];
		[self startDaemon];
	}
}

@end
