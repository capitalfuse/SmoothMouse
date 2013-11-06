
#import "Config.h"

#include "constants.h"
#include "debug.h"

@implementation Config

@synthesize mouseEnabled;
@synthesize trackpadEnabled;
@synthesize mouseVelocity;
@synthesize trackpadVelocity;
@synthesize mouseCurve;
@synthesize trackpadCurve;
@synthesize driver;
@synthesize forceDragRefreshEnabled;
@synthesize debugEnabled;
@synthesize memoryLoggingEnabled;
@synthesize timingsEnabled;
@synthesize sendAuxEventsEnabled;
@synthesize overlayEnabled;
@synthesize sayEnabled;
@synthesize latencyEnabled;

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
    sayEnabled = NO;
    latencyEnabled = NO;
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

        if ([argument isEqualToString: @"--latency"]) {
            [self setLatencyEnabled: YES];
            NSLog(@"Latency measuring enabled (EXPERIMENTAL!)");
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

    excludedApps = [dict objectForKey:SETTINGS_EXCLUDED_APPS];
    if (excludedApps) {
        excludedApps = [excludedApps copy];
    }

    if ([[Config instance] debugEnabled]) {
        NSLog(@"excludedApps = %@", excludedApps);
    }

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

    value = [dict valueForKey:SETTINGS_FORCE_DRAG_REFRESH];
    if (value) {
        [self setForceDragRefreshEnabled:[value boolValue]];
    } else {
        [self setForceDragRefreshEnabled:SETTINGS_FORCE_DRAG_REFRESH_DEFAULT];
    }

    [self setMouseCurve: [self getAccelerationCurveFromDict:dict withKey:SETTINGS_MOUSE_ACCELERATION_CURVE]];
    [self setTrackpadCurve: [self getAccelerationCurveFromDict:dict withKey:SETTINGS_TRACKPAD_ACCELERATION_CURVE]];

    return YES;
}

- (void)setActiveAppId:(NSString *)activeAppId {

    activeAppIsExcluded = NO;
    activeAppRequiresRefreshOnDrag = NO;
    activeAppRequiresMouseEventListener = NO; // currently no app uses this quirk
    activeAppRequiresTabletPointSubtype = NO; // currently no app uses this quirk, either

    // excluded
    if (excludedApps) {
        for (NSString *excludedApp in excludedApps) {
            if ([excludedApp isEqualToString:activeAppId]) {
                activeAppIsExcluded = YES;
            }
        }
    }

    if ([activeAppId isEqualToString:@"com.riotgames.LeagueofLegends.GameClient"]) {
        activeAppRequiresRefreshOnDrag = YES;
    }

    if ([activeAppId isEqualToString:@"com.aspyr.callofduty4"] ||
        [activeAppId isEqualToString:@"com.native-instruments.Traktor"] ||
        [activeAppId isEqualToString:@"com.ableton.live"] ||
        [activeAppId isEqualToString:@"net.maxon.cinema4d"] ||
        [activeAppId isEqualToString:@"com.macsoft.halo"]) {
        activeAppRequiresRefreshOnDrag = YES;
    }

    if ([self appId:activeAppId contains:@"Steam/steamapps/common/Half-Life 2/hl2_osx"] ||
        [self appId:activeAppId contains:@"Teeworlds.app/Contents/MacOS/teeworlds"]) {
        activeAppRequiresRefreshOnDrag = YES;
    }

    if ([[Config instance] debugEnabled]) {
        LOG(@"activeAppIsExcluded: %d, activeAppRequiresRefreshOnDrag: %d, activeAppRequiresMouseEventListener: %d, activeAppRequiresTabletPointSubtype: %d",
            activeAppIsExcluded,
            activeAppRequiresRefreshOnDrag,
            activeAppRequiresMouseEventListener,
            activeAppRequiresTabletPointSubtype);
    }
}

-(BOOL) appId:(NSString *)activeAppId contains:(NSString *)string {
    NSRange range;
    range = [activeAppId rangeOfString:string options:NSCaseInsensitiveSearch];
    if (range.location != NSNotFound) {
        return YES;
    }
    return NO;
}

-(BOOL) activeAppRequiresRefreshOnDrag {
    return activeAppRequiresRefreshOnDrag;
}

-(BOOL) activeAppIsExcluded {
    return activeAppIsExcluded;
}

-(BOOL) activeAppRequiresMouseEventListener {
    return activeAppRequiresMouseEventListener;
}

-(BOOL) activeAppRequiresTabletPointSubtype {
    return activeAppRequiresTabletPointSubtype;
}

@end
