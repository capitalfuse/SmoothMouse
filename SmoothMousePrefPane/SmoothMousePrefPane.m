#import "SmoothMousePrefPane.h"
#import "strings.h"

#import <ServiceManagement/ServiceManagement.h>


@implementation SmoothMousePrefPane

- (void)mainViewDidLoad
{
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
    
    /* Always enable start at login, and start daemon. */
    if (![self putLaunchdPlist]) {
        NSLog(@"Failed to enable start-at-login");
    }
    [self startDaemon];
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
        if (![self isDaemonRunning]) {
            [self startDaemon];
        }
    } else {
        if ([self isDaemonRunning]) {
            [self stopDaemon];
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
	NSError *error;
	NSMutableDictionary *job = [[[NSMutableDictionary alloc] init] autorelease];
	[job setObject:@"com.cyberic.smoothmouse" forKey:@"Label"];
	[job setObject:@"/usr/local/bin/smoothmoused" forKey:@"Program"];
	[job setObject:[NSNumber numberWithBool:YES] forKey:@"KeepAlive"];
	
	return SMJobSubmit(kSMDomainUserLaunchd, (CFDictionaryRef) job, NULL, (CFErrorRef*)&error);
}

- (BOOL)stopDaemon
{
	NSError *error;
	
	return SMJobRemove(kSMDomainUserLaunchd, (CFStringRef) @"com.cyberic.smoothmouse", NULL, TRUE, (CFErrorRef*)&error);
}

- (BOOL)startAtLoginEnabled
{
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: LAUNCHD_PLIST_FILENAME];
	
	return [fm fileExistsAtPath:file];
}

- (BOOL)putLaunchdPlist
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: LAUNCHD_PLIST_FILENAME];
	
	NSMutableDictionary *dict = [[[NSMutableDictionary alloc] init] autorelease];
	[dict setObject:@"com.cyberic.smoothmouse" forKey:@"Label"];
	[dict setObject:@"/usr/local/bin/smoothmoused" forKey:@"Program"];
	[dict setObject:[NSNumber numberWithBool:(0 != [startAtLogin state])] forKey:@"KeepAlive"];
	
	return [dict writeToFile:file atomically:YES];
}

- (BOOL)deleteLaunchdPlist
{
	NSError *error;
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: LAUNCHD_PLIST_FILENAME];
	
	return [fm removeItemAtPath:file error:&error];
}

- (double)getVelocityForMouse
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:file];
	NSNumber *value = [settings valueForKey:@"Mouse velocity"];
	return value ? [value doubleValue] : 0.5;
}

- (double)getVelocityForTrackpad
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:file];
	NSNumber *value = [settings valueForKey:@"Trackpad velocity"];
	return value ? [value doubleValue] : 0.5;
}

- (BOOL)getMouseEnabled
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:file];
	NSNumber *value = [settings valueForKey:@"Mouse enabled"];
	return value ? [value boolValue] : TRUE;
}

- (BOOL)getTrackpadEnabled
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:file];
	NSNumber *value = [settings valueForKey:@"Trackpad enabled"];
	return value ? [value boolValue] : TRUE;
}

- (NSString *)getAccelerationCurveForMouse {
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:file];
	NSString *value = [settings valueForKey:@"Mouse acceleration curve"];
	return value;
}

- (NSString *)getAccelerationCurveForTrackpad {
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:file];
	NSString *value = [settings valueForKey:@"Trackpad acceleration curve"];
	return value;
}

- (BOOL)saveVelocityForMouse:(double) valueMouse andTrackpad:(double) valueTrackpad;
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:file];
	
    NSNumber *num;

    num = [NSNumber numberWithDouble:valueMouse];
	[settings setValue:num forKey:@"Mouse velocity"];

    num = [NSNumber numberWithDouble:valueTrackpad];
	[settings setValue:num forKey:@"Trackpad velocity"];

	// TODO: does num need releasing here?
    return [settings writeToFile:file atomically:YES];
}

- (BOOL)saveAccelerationCurveForMouse:(NSString *) value {
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:file];
	[settings setValue:value forKey:@"Mouse acceleration curve"];
	return [settings writeToFile:file atomically:YES];
}

- (BOOL)saveAccelerationCurveForTrackpad:(NSString *) value {
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:file];
	[settings setValue:value forKey:@"Trackpad acceleration curve"];
	return [settings writeToFile:file atomically:YES];
}

- (BOOL)saveMouseEnabled:(BOOL) value
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:file];
	NSNumber *num = [NSNumber numberWithBool:value];
	[settings setValue:num forKey:@"Mouse enabled"];
	return [settings writeToFile:file atomically:YES];
}

- (BOOL)saveTrackpadEnabled:(BOOL) value
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:file];
	NSNumber *num = [NSNumber numberWithBool:value];
	[settings setValue:num forKey:@"Trackpad enabled"];
	return [settings writeToFile:file atomically:YES];
}

- (void)restartDaemonIfRunning {
	if ([self isDaemonRunning]) {
		[self stopDaemon];
		[self startDaemon];
	}
}

@end
