
#import "Configuration.h"

#include "constants.h"
#include "Debug.h"

@implementation Configuration

-(id)init
{
    LOG(@"enter");
    self = [super init];
    configuration = nil;
    configurationFilename = nil;
    connectedDevices = nil;
    return self;
}

-(BOOL) load
{
    LOG(@"enter");

    configurationFilename = [NSHomeDirectory() stringByAppendingPathComponent: PREFERENCES_FILENAME];
    [configurationFilename retain];

    NSMutableDictionary *plistContents = [NSMutableDictionary dictionaryWithContentsOfFile:configurationFilename];

    if (!plistContents) {
        NSLog(@"cannot open file %@", configurationFilename);
        return NO;
    }

    configuration = plistContents;

    [configuration retain];

    LOG(@"configuration: %@", configuration);

    return YES;
}

-(BOOL) save
{
    LOG(@"enter");
    return [configuration writeToFile:configurationFilename atomically:YES];
}

-(BOOL) writeDefaultConfiguration
{
    LOG(@"enter");
    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
                          [[[NSArray alloc] init] autorelease], SETTINGS_DEVICES,
                          [NSNumber numberWithInt:2], SETTINGS_DRIVER,
                          nil];

    NSString *file = [NSHomeDirectory() stringByAppendingPathComponent: PREFERENCES_FILENAME];

    [dict writeToFile:file atomically:YES];

    //[dict release];

    return YES;
}

-(NSMutableArray *) getDevices
{
    if (configuration) {
        NSMutableArray *devices = [configuration valueForKey:@"Devices"];
        //LOG(@"devices: %@", devices);
        return devices;
    } else {
        return nil;
    }
}

-(NSMutableDictionary *) getDeviceAtIndex: (int) index
{
    if (configuration) {
        NSMutableArray *devices = [configuration valueForKey:@"Devices"];
        if (index < [devices count]) {
            return [devices objectAtIndex:index];
        } else {
            return nil;
        }
    } else {
        return nil;
    }
}

-(int) getIndexForDeviceWithVendorID:(uint32_t)theVid andProductID:(uint32_t)thePid
{
    NSArray *devices = [self getDevices];

    if (devices) {
        int index = 0;
        for (NSDictionary *device in devices) {
            uint32_t vid, pid;

            if (![Configuration getIntegerInDictionary:device forKey:SETTINGS_VENDOR_ID withResult: &vid]) {
                LOG(@"Key %@ missing in device", SETTINGS_VENDOR_ID);
                continue;
            }

            if (![Configuration getIntegerInDictionary:device forKey:SETTINGS_PRODUCT_ID withResult: &pid]) {
                LOG(@"Key %@ missing in device", SETTINGS_PRODUCT_ID);
                continue;
            }

            if (vid == theVid && pid == thePid) {
                LOG(@"device: %p", device);
                return index;
            }

            index++;
        }
    }
    LOG(@"no such device");
    return -1;
}

-(BOOL) deviceExistsWithVendorID: (uint32_t) vid andProductID: (uint32_t) pid
{
    NSDictionary *device = [self getDeviceWithVendorID: vid andProductID: pid];
    LOG(@"device %d:%d exists? %p", vid, pid, device);
    return (device != nil);
}

-(NSDictionary *) getDeviceWithVendorID: (uint32_t) theVid andProductID: (uint32_t) thePid
{
    NSArray *devices = [self getDevices];

    if (devices) {
        for (NSDictionary *device in devices) {
            uint32_t vid, pid;
            
            if (![Configuration getIntegerInDictionary:device forKey:SETTINGS_VENDOR_ID withResult: &vid]) {
                LOG(@"Key %@ missing in device", SETTINGS_VENDOR_ID);
                continue;
            }
            if (![Configuration getIntegerInDictionary:device forKey:SETTINGS_PRODUCT_ID withResult: &pid]) {
                LOG(@"Key %@ missing in device", SETTINGS_PRODUCT_ID);
                continue;
            }

            if (vid == theVid && pid == thePid) {
                LOG(@"device: %p", device);
                return device;
            }
        }
    }
    LOG(@"no such device");
    return nil;
}

-(void) createDeviceFromKextDeviceInformation: (device_information_t *) information
{
    LOG(@"enter");

    NSMutableDictionary *device;

    // make sure it's not there already
    device = [self getDeviceWithVendorID: information->vendor_id andProductID: information->product_id];
    if (device) {
        LOG(@"device already exists :-(");
        [NSApp close];
    }

    device = [NSMutableDictionary dictionaryWithObjectsAndKeys:
              [NSNumber numberWithInt:information->vendor_id], SETTINGS_VENDOR_ID,
              [NSNumber numberWithInt:information->product_id], SETTINGS_PRODUCT_ID,
              [NSString stringWithUTF8String:information->manufacturer_string], SETTINGS_MANUFACTURER,
              [NSString stringWithUTF8String:information->product_string], SETTINGS_PRODUCT,
              [NSNumber numberWithDouble:SETTINGS_VELOCITY_DEFAULT], SETTINGS_VELOCITY,
              [NSNumber numberWithBool:SETTINGS_ENABLED_DEFAULT], SETTINGS_ENABLED,
              SETTINGS_ACCELERATION_CURVE_DEFAULT, SETTINGS_ACCELERATION_CURVE,
              nil];

    NSMutableArray *devices = [self getDevices];

    [devices addObject:device];

    [self save];

    LOG(@"configuration: %@", configuration);
}

-(BOOL) connectDeviceWithVendorID: (uint32_t) vid andProductID: (uint32_t) pid
{
    BOOL ok = NO;
    LOG(@"connecting device %d:%d", vid, pid);
    NSMutableDictionary *device = [self getDeviceWithVendorID: vid andProductID: pid];
    if (device) {
        if (connectedDevices == nil) {
            connectedDevices = [[NSMutableArray alloc] init];
        }
        if (![connectedDevices containsObject:device]) {
            [connectedDevices addObject:device];
            ok = YES;
        } else {
            LOG(@"already present as a connected device");
        }
    }
    LOG(@"connectDeviceWithVendorID: %d", ok);
    return ok;
}

-(BOOL) disconnectDeviceWithVendorID: (uint32_t) vid andProductID: (uint32_t) pid
{
    LOG(@"disconnecting device %d:%d", vid, pid);
    if (!connectedDevices) {
        LOG(@"No connected devices");
        return NO;
    }
    BOOL ok = NO;
    NSMutableDictionary *device = [self getDeviceWithVendorID: vid andProductID: pid];
    if (device) {
        [connectedDevices removeObject:device];
        ok = YES;
    }
    LOG(@"disconnectDeviceWithVendorID: %d", ok);
    return ok;
}

-(BOOL) deviceIsConnectedWithVendorID: (uint32_t) vid andProductID: (uint32_t) pid {
    BOOL isConnected = NO;
    NSMutableDictionary *device = [self getDeviceWithVendorID: vid andProductID: pid];
    if (device) {
        if ([connectedDevices containsObject:device]) {
            isConnected = YES;
        }
    }
    LOG(@"isConnected: %d", isConnected);
    return isConnected;
}

-(BOOL) anyDeviceIsEnabled {
    NSArray *devices = [self getDevices];

    if (devices) {
        for (NSDictionary *device in devices) {
            BOOL enabled;
            if (![Configuration getBoolInDictionary:device forKey:SETTINGS_ENABLED withResult: &enabled]) {
                LOG(@"Key %@ missing in device", SETTINGS_ENABLED);
                continue;
            }
            if (enabled) {
                return YES;
            }
        }
    }
    return NO;
}

+ (BOOL) getIntegerInDictionary: (NSDictionary *)dictionary forKey: (NSString *)key withResult: (uint32_t *)result
{
    NSNumber *number = [dictionary objectForKey:key];
    if (number && [number isKindOfClass:[NSNumber class]]) {
        *result = (uint32_t)[number integerValue];
        return YES;
    } else {
        return NO;
    }
}

+ (BOOL) getStringInDictionary: (NSDictionary *)dictionary forKey: (NSString *)key withResult: (NSString **)result
{
    NSString *string = [dictionary objectForKey:key];
    if (string && [string isKindOfClass:[NSString class]]) {
        *result = string;
        return YES;
    } else {
        return NO;
    }
}

+ (BOOL) getBoolInDictionary: (NSDictionary *)dictionary forKey: (NSString *)key withResult: (BOOL *)result
{
    NSNumber *number = [dictionary objectForKey:key];
    if (number && [number isKindOfClass:[NSNumber class]]) {
        *result = [number boolValue];
        return YES;
    } else {
        return NO;
    }
}

+ (BOOL) getDoubleInDictionary: (NSDictionary *)dictionary forKey: (NSString *)key withResult: (double *)result
{
    NSNumber *number = [dictionary objectForKey:key];
    if (number && [number isKindOfClass:[NSNumber class]]) {
        *result = [number doubleValue];
        return YES;
    } else {
        return NO;
    }
}

@end
