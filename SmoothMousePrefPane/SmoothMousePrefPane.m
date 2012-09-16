#import "SmoothMousePrefPane.h"
#import "strings.h"

#import <ServiceManagement/ServiceManagement.h>


@implementation SmoothMousePrefPane

- (void)mainViewDidLoad
{
	/* Daemon state */
	if ([self daemonRunning]) {
		[switchOnOff setTitle:@"Stop"];
		[status setStringValue:@"SmoothMouse is running"];
	} else {
		[switchOnOff setTitle:@"Start"];
		[status setStringValue:@"SmoothMouse is stopped"];
	}
	
	/* Start at login state */
	if ([self startAtLoginEnabled]) {
		[startAtLogin setState:1];
	} else {
		[startAtLogin setState:0];
	}
	
    /* Mouse enabled state */
    if ([self isMouseEnabled]) {
        [enableForMouse setState:1];
    } else {
        [enableForMouse setState:0];
    }
    
    /* Trackpad enabled state */
    if ([self isTrackpadEnabled]) {
        [enableForTrackpad setState:1];
    } else {
        [enableForTrackpad setState:0];
    }
    
	/* velocity value */
	[velocity setDoubleValue:[self velocity]];
}

- (IBAction)pressSwitchOnOff:(id) sender
{
	if ([self daemonRunning]) {
		/* Stop */
		if ([self stopDaemon]) {
			[switchOnOff setTitle:@"Start"];
			[status setStringValue:@"SmoothMouse is stopped"];
		}
	} else {
		/* Start */
		if ([self startDaemon]) {
			[switchOnOff setTitle:@"Stop"];
			[status setStringValue:@"SmoothMouse is running"];
		}
	}
}

- (IBAction)pressStartAtLogin:(id) sender
{
	if ([self startAtLoginEnabled]) {
		/* Disable */
		if ([self deleteLaunchdPlist]) {
			[startAtLogin setState:0];
		}
	} else {
		/* Enable */
		if ([self putLaunchdPlist]) {
			[startAtLogin setState:1];
		}
	}
}

- (IBAction)changeVelocity:(id) sender
{
	[self saveVelocity:[velocity doubleValue]];
	
	if ([self daemonRunning]) {
		[self stopDaemon];
		[self startDaemon];
	}
}

- (IBAction)pressEnableDisableMouse:(id) sender
{
	[self saveMouseEnabled:[enableForMouse state]];
	
	if ([self daemonRunning]) {
		[self stopDaemon];
		[self startDaemon];
	}
}

- (IBAction)pressEnableDisableTrackpad:(id) sender {
	[self saveTrackpadEnabled:[enableForTrackpad state]];
	
	if ([self daemonRunning]) {
		[self stopDaemon];
		[self startDaemon];
	}   
}

- (BOOL)daemonRunning
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


- (double)velocity
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:file];
	NSNumber *value = [settings valueForKey:@"velocity"];
	return value ? [value doubleValue] : 0.5;
}

- (BOOL)isMouseEnabled
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:file];
	NSNumber *value = [settings valueForKey:@"Mouse enabled"];
	return value ? [value boolValue] : TRUE;
}

- (BOOL)isTrackpadEnabled
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:file];
	NSNumber *value = [settings valueForKey:@"Trackpad enabled"];
	return value ? [value boolValue] : TRUE;
}

- (BOOL)saveVelocity:(double) value
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PLIST_FILENAME];
	NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:file];
	NSNumber *num = [NSNumber numberWithDouble:value];
	[settings setValue:num forKey:@"velocity"];
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

@end
