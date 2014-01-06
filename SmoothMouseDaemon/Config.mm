
#import "Config.h"

#include "constants.h"
#include "debug.h"

#include <string.h>

@implementation Config
@synthesize driver;
@synthesize forceDragRefreshEnabled;
@synthesize keyboardEnabled;
@synthesize debugEnabled;
@synthesize memoryLoggingEnabled;
@synthesize timingsEnabled;
@synthesize sendAuxEventsEnabled;
@synthesize overlayEnabled;
@synthesize sayEnabled;
@synthesize latencyEnabled;
@synthesize mouseEnabled;
@synthesize trackpadEnabled;

static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;

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
    memset(keyboardConfiguration, 0, KEYBOARD_CONFIGURATION_SIZE);
    mouseEnabled = NO;
    trackpadEnabled = NO;
    return self;
}

const char *get_acceleration_string(AccelerationCurve curve) {
    switch (curve) {
        case ACCELERATION_CURVE_LINEAR: return "LINEAR";
        case ACCELERATION_CURVE_WINDOWS: return "WINDOWS";
        case ACCELERATION_CURVE_OSX: return "OSX";
        default: return "?";
    }
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

-(BOOL) readSettingsPlist
{
    NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PREFERENCES_FILENAME];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:file];
    NSArray *devicesFromPlist;

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
    NSString *stringValue;

    devicesFromPlist = [dict valueForKey:@"Devices"];
    if (devicesFromPlist) {
        pthread_mutex_lock(&mutex);
        BOOL ok = YES;
        devices.clear();
        for (NSDictionary *deviceInfo in devicesFromPlist) {
            DeviceInfo newDevice;

            if (![self getIntegerInDictionary:deviceInfo forKey:SETTINGS_VENDOR_ID withResult: &newDevice.vendor_id]) {
                NSLog(@"Failed to read VendorID");
                ok = NO;
                break;
            }
            if (![self getIntegerInDictionary:deviceInfo forKey:SETTINGS_PRODUCT_ID withResult: &newDevice.product_id]) {
                NSLog(@"Failed to read ProductID");
                ok = NO;
                break;
            }
            if (![self getStringInDictionary:deviceInfo forKey:SETTINGS_MANUFACTURER withResult: newDevice.manufacturer]) {
                NSLog(@"Failed to read Manufacturer");
                ok = NO;
                break;
            }
            if (![self getStringInDictionary:deviceInfo forKey:SETTINGS_PRODUCT withResult: newDevice.product]) {
                NSLog(@"Failed to read Product");
                ok = NO;
                break;
            }
            if (![self getDoubleInDictionary:deviceInfo forKey:SETTINGS_VELOCITY withResult: &newDevice.velocity]) {
                NSLog(@"Failed to read Velocity");
                ok = NO;
                break;
            }
            if (![self getAccelerationCurveFromDictionary:deviceInfo withKey:SETTINGS_ACCELERATION_CURVE withResult: &newDevice.curve]) {
                NSLog(@"Failed to read Curve");
                ok = NO;
                break;
            }
            if (![self getBoolInDictionary:deviceInfo forKey:SETTINGS_ENABLED withResult: (BOOL *)&newDevice.enabled]) {
                NSLog(@"Failed to read Enabled");
                ok = NO;
                break;
            }

            newDevice.connected = false;
            newDevice.is_trackpad = false;

            LOG(@"Configured Device: %s (%s)", newDevice.product.c_str(), newDevice.manufacturer.c_str());
            LOG(@"  VendorID: %u, ProductID: %u, Velocity: %f, Curve: %s", newDevice.vendor_id, newDevice.product_id, newDevice.velocity, get_acceleration_string(newDevice.curve));
            devices.insert(devices.begin(), newDevice);
        }
        pthread_mutex_unlock(&mutex);
        if (!ok) {
            return NO;
        }
        [self listAllDevices];
    } else {
        LOG(@"No devices found in plist");
        return NO;
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

    stringValue = [dict valueForKey:SETTINGS_KEYBOARD_ENABLED];
    if (stringValue) {
        [self setKeyboardEnabled:YES];
        NSArray *tokens = [stringValue componentsSeparatedByString: @","];
        for (NSString *token in tokens) {
            int i = (int) [token integerValue];
            NSLog(@"Enabled key: %d", i);
            keyboardConfiguration[i] = 1;
        }
    } else {
        [self setKeyboardEnabled:NO];
    }

    return YES;
}

- (BOOL) getIntegerInDictionary: (NSDictionary *)dictionary forKey: (NSString *)key withResult: (uint32_t *)result
{
    NSNumber *number = [dictionary objectForKey:key];
    if (number && [number isKindOfClass:[NSNumber class]]) {
        *result = (uint32_t)[number integerValue];
        return YES;
    } else {
        return NO;
    }
}

- (BOOL) getStringInDictionary: (NSDictionary *)dictionary forKey: (NSString *)key withResult: (std::string &)result
{
    NSString *string = [dictionary objectForKey:key];
    if (string && [string isKindOfClass:[NSString class]]) {
        std::string s = [string UTF8String];
        result = s;
        return YES;
    } else {
        return NO;
    }
}

- (BOOL) getBoolInDictionary: (NSDictionary *)dictionary forKey: (NSString *)key withResult: (BOOL *)result
{
    NSNumber *number = [dictionary objectForKey:key];
    if (number && [number isKindOfClass:[NSNumber class]]) {
        *result = [number boolValue];
        return YES;
    } else {
        return NO;
    }
}

- (BOOL) getDoubleInDictionary: (NSDictionary *)dictionary forKey: (NSString *)key withResult: (double *)result
{
    NSNumber *number = [dictionary objectForKey:key];
    if (number && [number isKindOfClass:[NSNumber class]]) {
        *result = [number doubleValue];
        return YES;
    } else {
        return NO;
    }
}

-(BOOL) getAccelerationCurveFromDictionary:(NSDictionary *)dictionary withKey:(NSString *)key withResult: (AccelerationCurve *)result
{
    NSString *value;
    value = [dictionary valueForKey:key];
    if (value && [value isKindOfClass:[NSString class]]) {
        if ([value compare:@"Windows"] == NSOrderedSame) {
            *result = ACCELERATION_CURVE_WINDOWS;
            return YES;
        }
        if ([value compare:@"OS X"] == NSOrderedSame) {
            *result = ACCELERATION_CURVE_OSX;
            return YES;
        }
        if ([value compare:@"Off"] == NSOrderedSame) {
            *result = ACCELERATION_CURVE_LINEAR;
            return YES;
        }
    }
    return NO;
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
        [activeAppId isEqualToString:@"com.macsoft.halo"] ||
        [activeAppId isEqualToString:@"org.mixxx.mixxx"] ||
        [activeAppId isEqualToString:@"com.turbine.lotroclient"] ||
        [activeAppId isEqualToString:@"com.transgaming.maxpayne3.steam"] ||
        [activeAppId isEqualToString:@"com.aspyr.bioshock3.steam"] ||
        [activeAppId isEqualToString:@"com.transgaming.thedarknessii"] ||
        [activeAppId isEqualToString:@"com.doublefine.brutallegend"] ||
        [activeAppId isEqualToString:@"com.transgaming.guildwars2"]) {
        activeAppRequiresRefreshOnDrag = YES;
    }

    // Steam/steamapps/common/Half-Life 2/hl2_osx
    // Steam/steamapps/common/Counter-Strike Source/hl2_osx
    if ([self appId:activeAppId contains:@"hl2_osx"] ||
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

-(BOOL) getKeyboardConfiguration: (char *)keyboardConfig {
    memcpy(keyboardConfig, keyboardConfiguration, KEYBOARD_CONFIGURATION_SIZE);
    return YES;
}

-(BOOL) getDeviceWithDeviceType:(device_type_t)deviceType andVendorID:(uint32_t)vendorID andProductID:(uint32_t)productID withResult:(DeviceInfo *)theResult
{
    if (deviceType != DEVICE_TYPE_POINTING ) {
        return NO;
    }
    BOOL found = NO;
    pthread_mutex_lock(&mutex);
    std::vector<DeviceInfo>::iterator iterator;
    for (iterator = devices.begin(); iterator != devices.end(); iterator++) {
        DeviceInfo *deviceInfo = &*iterator;
        if (deviceInfo->vendor_id == vendorID && deviceInfo->product_id == productID) {
            *theResult = *deviceInfo;
            found = YES;
            break;
        }
    }
    pthread_mutex_unlock(&mutex);
    return found;
}

-(size_t) getNumberOfDevices {
    size_t count;
    pthread_mutex_lock(&mutex);
    count = devices.size();
    pthread_mutex_unlock(&mutex);
    return count;
}

-(void) connectDeviceWithDeviceType:(device_type_t)deviceType andVendorID:(uint32_t)vendorID andProductID:(uint32_t)productID {
    pthread_mutex_lock(&mutex);

    std::vector<DeviceInfo>::iterator iterator;
    for (iterator = devices.begin(); iterator != devices.end(); iterator++) {
        DeviceInfo *deviceInfo = &*iterator;
        if (deviceInfo->vendor_id == vendorID && deviceInfo->product_id == productID) {
            deviceInfo->connected = true;
            LOG(@"Connected device %d:%d", vendorID, productID);
            if ([self anyConnectedAndEnabledMice]) {
                LOG(@"Enabled mouse");
                [self setMouseEnabled:YES];
            }
            if ([self anyConnectedAndEnabledTrackpads]) {
                LOG(@"Enabled trackpad");
                [self setTrackpadEnabled:YES];
            }
        }
    }

    pthread_mutex_unlock(&mutex);
}

-(void) disconnectDeviceWithDeviceType:(device_type_t)deviceType andVendorID:(uint32_t)vendorID andProductID:(uint32_t)productID
{
    pthread_mutex_lock(&mutex);

    LOG(@"DISCONNECT");
    std::vector<DeviceInfo>::iterator iterator;
    for (iterator = devices.begin(); iterator != devices.end(); iterator++) {
        DeviceInfo *deviceInfo = &*iterator;
        if (deviceInfo->vendor_id == vendorID && deviceInfo->product_id == productID) {
            deviceInfo->connected = false;
            LOG(@"Disconnected device %d:%d", vendorID, productID);
            if (![self anyConnectedAndEnabledMice]) {
                LOG(@"Disabled mouse");
                [self setMouseEnabled:NO];
            }
            if (![self anyConnectedAndEnabledTrackpads]) {
                LOG(@"Disabled trackpad");
                [self setTrackpadEnabled:NO];
            }
        }
    }

    pthread_mutex_unlock(&mutex);
}

-(BOOL) anyConnectedAndEnabledMice {
    BOOL found = NO;
    std::vector<DeviceInfo>::iterator iterator;
    for (iterator = devices.begin(); iterator != devices.end(); iterator++) {
        DeviceInfo *deviceInfo = &*iterator;
        if (!deviceInfo->is_trackpad && deviceInfo->connected && deviceInfo->enabled) {
            LOG(@"found %d:%d trackpad: %d", deviceInfo->vendor_id, deviceInfo->product_id, deviceInfo->is_trackpad);
            found = YES;
            break;
        }
    }
    return found;
}

-(BOOL) anyConnectedAndEnabledTrackpads {
    BOOL found = NO;
    std::vector<DeviceInfo>::iterator iterator;
    for (iterator = devices.begin(); iterator != devices.end(); iterator++) {
        DeviceInfo *deviceInfo = &*iterator;
        if (deviceInfo->is_trackpad && deviceInfo->connected && deviceInfo->enabled) {
            found = YES;
            break;
        }
    }
    return found;
}

-(void) listAllDevices {
    std::vector<DeviceInfo>::iterator iterator;
    LOG(@"--- <DEVICES> ---");
    for (iterator = devices.begin(); iterator != devices.end(); iterator++) {
        DeviceInfo *deviceInfo = &*iterator;
        LOG(@"%d:%d enabled: %d, connected: %d, trackpad: %d (0 means mouse or unknown)", deviceInfo->vendor_id, deviceInfo->product_id, deviceInfo->enabled, deviceInfo->connected, deviceInfo->is_trackpad);
    }
    LOG(@"--- </DEVICES> ---");
}

-(BOOL) configureDevices:(Kext *)kext {
    pthread_mutex_lock(&mutex);
    [self setMouseEnabled:YES];
    [self setTrackpadEnabled:YES];
    std::vector<DeviceInfo>::iterator iterator;
    for (iterator = devices.begin(); iterator != devices.end(); iterator++) {
        DeviceInfo *deviceInfo = &*iterator;
        device_configuration_t device_config;
        memset(&device_config, 0, sizeof(device_configuration_t));
        device_config.device_type = DEVICE_TYPE_POINTING;
        device_config.vendor_id = deviceInfo->vendor_id;
        device_config.product_id = deviceInfo->product_id;
        device_config.enabled = deviceInfo->enabled;
        [kext kextMethodConfigureDevice:&device_config];
        LOG(@"%s POINTING device: VendorID: %u, ProductID: %u, Manufacturer: '%s', Product: '%s'",
            (deviceInfo->enabled ? "Enabled" : "Disabled"), deviceInfo->vendor_id, deviceInfo->product_id, deviceInfo->manufacturer.c_str(), deviceInfo->product.c_str());

        device_information_t kextDeviceInfo;
        BOOL ok = [kext kextMethodGetDeviceInformation: &kextDeviceInfo forDeviceWithDeviceType:DEVICE_TYPE_POINTING andVendorId: deviceInfo->vendor_id andProductID: deviceInfo->product_id];
        if (ok) {
            deviceInfo->is_trackpad = kextDeviceInfo.pointing.is_trackpad;
            LOG(@"setting %d:%d to trackpad: %d", deviceInfo->vendor_id, deviceInfo->product_id, deviceInfo->is_trackpad);
        } else {
            LOG(@"could not get device info for %d:%d", deviceInfo->vendor_id, deviceInfo->product_id);
        }
    }
    if ([self anyConnectedAndEnabledMice]) {
        LOG(@"Enabled mouse");
        [self setMouseEnabled:YES];
    }
    if ([self anyConnectedAndEnabledTrackpads]) {
        LOG(@"Enabled trackpad");
        [self setTrackpadEnabled:YES];
    }
    pthread_mutex_unlock(&mutex);
    return YES;
}

@end
