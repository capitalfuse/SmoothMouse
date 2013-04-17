
#import "Config.h"

#include "constants.h"

@implementation Config

@synthesize mouseEnabled;
@synthesize trackpadEnabled;
@synthesize mouseVelocity;
@synthesize trackpadVelocity;
@synthesize mouseCurve;
@synthesize trackpadCurve;
@synthesize driver;
@synthesize debugEnabled;
@synthesize memoryLoggingEnabled;
@synthesize timingsEnabled;
@synthesize sendAuxEventsEnabled;
@synthesize activeAppBundleId;
@synthesize overlayEnabled;
@synthesize sayEnabled;

+(Config *) instance
{
    static Config* instance = nil;

    if (instance == nil) {
        instance = [[Config alloc] init];
    }

    return instance;
}

-(id)init
{
    self = [super init];
    debugEnabled = NO;
    memoryLoggingEnabled = NO;
    timingsEnabled = NO;
    sendAuxEventsEnabled = NO;
    overlayEnabled = NO;
    return self;
}

-(BOOL) parseCommandLineArguments {
    NSArray *arguments = [[NSProcessInfo processInfo] arguments];

    for (NSString *argument in arguments) {
        if ([argument isEqualToString: @"--debug"]) {
            [self setDebugEnabled: YES];
            NSLog(@"Debug mode enabled");
        }

        if ([argument isEqualToString: @"--memory"]) {
            [self setMemoryLoggingEnabled: YES];
            NSLog(@"Memory logging enabled");
        }

        if ([argument isEqualToString: @"--timings"]) {
            [self setTimingsEnabled: YES];
            NSLog(@"Timing logging enabled");
        }

        if ([argument isEqualToString: @"--aux"]) {
            [self setSendAuxEventsEnabled: YES];
            NSLog(@"Sending AUX events enabled");
        }

        if ([argument isEqualToString: @"--overlay"]) {
            [self setOverlayEnabled: YES];
            NSLog(@"Overlay enabled (EXPERIMENTAL!)");
        }

        if ([argument isEqualToString: @"--say"]) {
            [self setSayEnabled: YES];
            NSLog(@"Say enabled (EXPERIMENTAL!)");
        }
    }

    return YES;
}

-(AccelerationCurve) getAccelerationCurveFromDict:(NSDictionary *)dictionary withKey:(NSString *)key {
    NSString *value;
    value = [dictionary valueForKey:key];
    if (value) {
        if ([value compare:@"Windows"] == NSOrderedSame) {
            return ACCELERATION_CURVE_WINDOWS;
        }
        if ([value compare:@"OS X"] == NSOrderedSame) {
            return ACCELERATION_CURVE_OSX;
        }
    }
    return ACCELERATION_CURVE_LINEAR;
}

-(BOOL) readSettingsPlist
{
    NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PREFERENCES_FILENAME];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:file];

    if (!dict) {
        NSLog(@"cannot open file %@", file);
        return NO;
    }

    NSLog(@"found %@", file);

    NSNumber *value;

    value = [dict valueForKey:SETTINGS_MOUSE_ENABLED];
    if (value) {
        [self setMouseEnabled: [value boolValue]];
    } else {
        return NO;
    }

    value = [dict valueForKey:SETTINGS_TRACKPAD_ENABLED];
    if (value) {
        [self setTrackpadEnabled: [value boolValue]];
    } else {
        return NO;
    }

    value = [dict valueForKey:SETTINGS_MOUSE_VELOCITY];
    if (value) {
        [self setMouseVelocity: [value doubleValue]];
    } else {
        [self setMouseVelocity: 1.0];
    }

    value = [dict valueForKey:SETTINGS_TRACKPAD_VELOCITY];
    if (value) {
        [self setTrackpadVelocity: [value doubleValue]];
    } else {
        [self setTrackpadVelocity: 1.0];
    }

    value = [dict valueForKey:SETTINGS_DRIVER];
    if (value) {
        [self setDriver:(Driver)[value intValue]];
    } else {
        [self setDriver:(Driver) SETTINGS_DRIVER_DEFAULT];
    }

    [self setMouseCurve: [self getAccelerationCurveFromDict:dict withKey:SETTINGS_MOUSE_ACCELERATION_CURVE]];
    [self setTrackpadCurve: [self getAccelerationCurveFromDict:dict withKey:SETTINGS_TRACKPAD_ACCELERATION_CURVE]];

    return YES;
}

@end
