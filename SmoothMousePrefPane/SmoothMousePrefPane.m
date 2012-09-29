#import "SmoothMousePrefPane.h"
#import "constants.h"

#import <ServiceManagement/ServiceManagement.h>


@implementation SmoothMousePrefPane

- (void)mainViewDidLoad
{
    if (![self settingsFileExists]) {
        [self saveDefaultSettingsFile];
        NSLog(@"Default settings saved");
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
    
	/* Velocity values */
	[velocityForMouse setDoubleValue:[self getVelocityForMouse]];
	[velocityForTrackpad setDoubleValue:[self getVelocityForTrackpad]];
}

-(BOOL) settingsFileExists
{
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	
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
    
    NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
    
    [dict writeToFile:file atomically:YES];
}

- (IBAction)changeVelocity:(id) sender
{
	[self saveVelocityForMouse:[velocityForMouse doubleValue] andTrackpad:[velocityForTrackpad doubleValue]];
    [self restartDaemonIfRunning];
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
    NSTask *task;
    task = [[NSTask alloc] init];
    [task setLaunchPath: @"/bin/launchctl"];
    
    NSArray *arguments;
    NSString *plistFile = [NSHomeDirectory() stringByAppendingPathComponent: LAUNCHD_PLIST_FILENAME];
    arguments = [NSArray arrayWithObjects: @"load", plistFile, nil];
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
    //NSLog (@"launchctl returned:\n%@", string);
    
    [string release];
    [task release];
    //[plistFile release];
}

- (BOOL)stopDaemon
{
    NSTask *task;
    task = [[NSTask alloc] init];
    [task setLaunchPath: @"/bin/launchctl"];
    
    NSArray *arguments;
    NSString *plistFile = [NSHomeDirectory() stringByAppendingPathComponent: LAUNCHD_PLIST_FILENAME];
    arguments = [NSArray arrayWithObjects: @"unload", plistFile, nil];
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
    //NSLog (@"launchctl returned:\n%@", string);
    
    [string release];
    [task release];
    //[plistFile release];
}

- (BOOL)startAtLoginEnabled
{
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: LAUNCHD_PLIST_FILENAME];
	
	return [fm fileExistsAtPath:file];
}

- (BOOL)enableStartAtLogin:(BOOL) enable
{
    if (enable) {
        NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: LAUNCHD_PLIST_FILENAME];
        
        NSMutableDictionary *dict = [[[NSMutableDictionary alloc] init] autorelease];
        [dict setObject:@"com.cyberic.smoothmouse" forKey:@"Label"];
        [dict setObject:DAEMON_FILENAME forKey:@"Program"];
//        [dict setObject:[NSNumber numberWithBool:enable] forKey:@"KeepAlive"];
        NSMutableDictionary *dict2 = [[[NSMutableDictionary alloc] init] autorelease];
        [dict2 setObject:[NSNumber numberWithBool:true] forKey:@"SuccessfulExit"];
        [dict setObject:dict2 forKey:@"KeepAlive"];
        return [dict writeToFile:file atomically:YES];
    } else {
        NSError *error;
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: LAUNCHD_PLIST_FILENAME];
        
        return [fm removeItemAtPath:file error:&error];
    }
}

- (double)getVelocityForMouse
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:file];
	NSNumber *value = [settings valueForKey:SETTINGS_MOUSE_VELOCITY];
	return value ? [value doubleValue] : SETTINGS_MOUSE_VELOCITY_DEFAULT;
}

- (double)getVelocityForTrackpad
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:file];
	NSNumber *value = [settings valueForKey:SETTINGS_TRACKPAD_VELOCITY];
	return value ? [value doubleValue] : SETTINGS_TRACKPAD_VELOCITY_DEFAULT;
}

- (BOOL)getMouseEnabled
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:file];
	NSNumber *value = [settings valueForKey:SETTINGS_MOUSE_ENABLED];
	return value ? [value boolValue] : FALSE;
}

- (BOOL)getTrackpadEnabled
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:file];
	NSNumber *value = [settings valueForKey:SETTINGS_TRACKPAD_ENABLED];
	return value ? [value boolValue] : FALSE;
}

- (NSString *)getAccelerationCurveForMouse {
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:file];
	NSString *value = [settings valueForKey:SETTINGS_MOUSE_ACCELERATION_CURVE];
	return value;
}

- (NSString *)getAccelerationCurveForTrackpad {
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:file];
	NSString *value = [settings valueForKey:SETTINGS_TRACKPAD_ACCELERATION_CURVE];
	return value;
}

- (BOOL)saveVelocityForMouse:(double) valueMouse andTrackpad:(double) valueTrackpad;
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
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
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:file];
	[settings setValue:value forKey:SETTINGS_MOUSE_ACCELERATION_CURVE];
	return [settings writeToFile:file atomically:YES];
}

- (BOOL)saveAccelerationCurveForTrackpad:(NSString *) value {
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:file];
	[settings setValue:value forKey:SETTINGS_TRACKPAD_ACCELERATION_CURVE];
	return [settings writeToFile:file atomically:YES];
}

- (BOOL)saveMouseEnabled:(BOOL) value
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:file];
	NSNumber *num = [NSNumber numberWithBool:value];
	[settings setValue:num forKey:SETTINGS_MOUSE_ENABLED];
	return [settings writeToFile:file atomically:YES];
}

- (BOOL)saveTrackpadEnabled:(BOOL) value
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
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
