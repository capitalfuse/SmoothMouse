
#import <Foundation/Foundation.h>

#include "KextInterface.h"

@interface Configuration : NSObject {
    NSString *configurationFilename;
    NSMutableDictionary *configuration;
}

-(id) init;
-(BOOL) load;
-(BOOL) save;
-(BOOL) writeDefaultConfiguration;
-(NSMutableArray *) getDevices;
-(BOOL) deviceExistsWithVendorID: (uint32_t) vid andProductID: (uint32_t) pid;
-(NSMutableDictionary *) getDeviceWithVendorID: (uint32_t) vid andProductID: (uint32_t) pid;
-(void) createDeviceFromKextDeviceInformation: (device_information_t *) information;

@end
