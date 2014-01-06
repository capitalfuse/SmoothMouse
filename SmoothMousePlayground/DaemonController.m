
#import "DaemonController.h"

#import "constants.h"

#import <ServiceManagement/ServiceManagement.h>

// umask
#include <sys/types.h>
#include <sys/stat.h>

#import "Debug.h"

@implementation DaemonController

- (BOOL)stop
{
    BOOL isRunning = [self isRunning];

    LOG(@"running: %d", isRunning);

    NSArray *arguments;
    NSString *plistFile = [NSHomeDirectory() stringByAppendingPathComponent: LAUNCH_AGENT_DAEMON_FILENAME];
    arguments = [NSArray arrayWithObjects: @"unload", plistFile, nil];

    BOOL ok = [self launchExecutable: @"/bin/launchctl" withArguments:arguments];

    [self enableStartAtLogin:NO];

    return ok;
}

- (BOOL)start
{
    BOOL isRunning = [self isRunning];

    LOG(@"START, running: %d", isRunning);

    [self enableStartAtLogin:YES];

    if ([self isRunning]) {
        return [self update];
    } else {
        NSArray *arguments;
        NSString *plistFile = [NSHomeDirectory() stringByAppendingPathComponent: LAUNCH_AGENT_DAEMON_FILENAME];
        arguments = [NSArray arrayWithObjects: @"load", plistFile, nil];
        return [self launchExecutable: @"/bin/launchctl" withArguments:arguments];
    }
}

- (BOOL) update
{
    LOG(@"enter");
    NSArray *arguments = [NSArray arrayWithObjects: @"-SIGUSR1", @"SmoothMouseDaemon", nil];
    return [self launchExecutable: @"/usr/bin/killall" withArguments:arguments];
}

- (BOOL) isRunning;
{
    BOOL running = NO;
	CFDictionaryRef job;

	job = SMJobCopyDictionary(kSMDomainUserLaunchd, (CFStringRef)@"com.cyberic.smoothmouse2"); // TODO: constant

	if (job) {
		CFRelease(job);
		running = YES;
	}

    return running;
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

    LOG(@"launched executable %@ with arguments %@", executable, arguments);

    return YES;
}

- (BOOL)enableStartAtLogin:(BOOL) enable
{
    NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: LAUNCH_AGENT_DAEMON_FILENAME];
    if (enable) {
        [self createLaunchAgentsDirectory];
        NSMutableDictionary *dict = [[[NSMutableDictionary alloc] init] autorelease];
        [dict setObject:@"com.cyberic.smoothmouse2" forKey:@"Label"];
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

-(void)createLaunchAgentsDirectory {
    mode_t oldMask = umask(S_IRWXO | S_IRWXG);

    NSFileManager *filemgr = [NSFileManager defaultManager];
    NSString *launchAgentsDirectory = [NSHomeDirectory() stringByAppendingPathComponent: @"/Library/LaunchAgents"];
    [filemgr createDirectoryAtPath: launchAgentsDirectory withIntermediateDirectories:YES attributes: nil error:nil];

    (void) umask(oldMask);
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

- (BOOL)isStartAtLoginEnabled
{
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: LAUNCH_AGENT_DAEMON_FILENAME];

	return [fm fileExistsAtPath:file];
}

@end
