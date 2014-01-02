
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
    return self;
}

-(BOOL) load
{
    LOG(@"enter");

    configurationFilename = [NSHomeDirectory() stringByAppendingPathComponent: PREFERENCES_FILENAME];
    NSMutableDictionary *plistContents = [NSMutableDictionary dictionaryWithContentsOfFile:configurationFilename];

    if (!plistContents) {
        NSLog(@"cannot open file %@", configurationFilename);
        return NO;
    }

    configuration = plistContents;

    [configuration retain];

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
                          [[[NSDictionary alloc] init] autorelease], @"Devices",
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
            if (![self getIntegerInDictionary:device forKey:@"VendorID" withResult: &vid]) {
                LOG(@"Failed to read VendorID");
                continue;
            }
            if (![self getIntegerInDictionary:device forKey:@"ProductID" withResult: &pid]) {
                LOG(@"Failed to read ProductID");
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

- (BOOL) getStringInDictionary: (NSDictionary *)dictionary forKey: (NSString *)key withResult: (NSString **)result
{
    NSString *string = [dictionary objectForKey:key];
    if (string && [string isKindOfClass:[NSString class]]) {
        *result = string;
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

@end
