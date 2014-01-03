
#import <Foundation/Foundation.h>

#include "KextInterface.h"

@interface Configuration : NSObject {
    NSString *configurationFilename;
    NSMutableDictionary *configuration;
    NSMutableArray *connectedDevices;
}

-(id) init;
-(BOOL) load;
-(BOOL) save;
-(BOOL) writeDefaultConfiguration;
-(NSMutableArray *) getDevices;
-(NSMutableDictionary *) getDeviceAtIndex: (int) index;
-(BOOL) deviceExistsWithVendorID: (uint32_t) vid andProductID: (uint32_t) pid;
-(NSMutableDictionary *) getDeviceWithVendorID: (uint32_t) vid andProductID: (uint32_t) pid;
-(void) createDeviceFromKextDeviceInformation: (device_information_t *) information;
-(BOOL) connectDeviceWithVendorID: (uint32_t) vid andProductID: (uint32_t) pid;
-(BOOL) disconnectDeviceWithVendorID: (uint32_t) vid andProductID: (uint32_t) pid;
-(BOOL) deviceIsConnectedWithVendorID: (uint32_t) vid andProductID: (uint32_t) pid;

+ (BOOL) getIntegerInDictionary: (NSDictionary *)dictionary forKey: (NSString *)key withResult: (uint32_t *)result;
+ (BOOL) getStringInDictionary: (NSDictionary *)dictionary forKey: (NSString *)key withResult: (NSString **)result;
+ (BOOL) getBoolInDictionary: (NSDictionary *)dictionary forKey: (NSString *)key withResult: (BOOL *)result;
+ (BOOL) getDoubleInDictionary: (NSDictionary *)dictionary forKey: (NSString *)key withResult: (double *)result;

@end
