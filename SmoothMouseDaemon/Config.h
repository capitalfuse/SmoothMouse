
#import <Foundation/Foundation.h>

#import "mouse.h"
#import "driver.h"
#include "Kext.h"

#include <string>
#include <vector>

typedef struct {
    uint32_t vendor_id;
    uint32_t product_id;
    std::string manufacturer;
    std::string product;
    double velocity;
    AccelerationCurve curve;
    bool enabled;
} DeviceInfo;

@interface Config : NSObject {
    // from plist
    std::vector<DeviceInfo> devices;
    Driver driver;
    BOOL forceDragRefreshEnabled;
    BOOL keyboardEnabled;

    // from command line
    BOOL debugEnabled;
    BOOL memoryLoggingEnabled;
    BOOL timingsEnabled;
    BOOL sendAuxEventsEnabled;
    BOOL overlayEnabled;
    BOOL sayEnabled;
    BOOL latencyEnabled;

    BOOL activeAppRequiresRefreshOnDrag;
    BOOL activeAppIsExcluded;
    BOOL activeAppRequiresMouseEventListener;
    BOOL activeAppRequiresTabletPointSubtype;

    char keyboardConfiguration[KEYBOARD_CONFIGURATION_SIZE];

    NSArray *excludedApps;

    BOOL mouseEnabled;
    BOOL trackpadEnabled;
}

@property Driver driver;
@property BOOL forceDragRefreshEnabled;
@property BOOL keyboardEnabled;
@property BOOL debugEnabled;
@property BOOL memoryLoggingEnabled;
@property BOOL timingsEnabled;
@property BOOL sendAuxEventsEnabled;
@property BOOL overlayEnabled;
@property BOOL sayEnabled;
@property BOOL latencyEnabled;
@property BOOL mouseEnabled;
@property BOOL trackpadEnabled;

+(Config *) instance;
-(id) init;
-(BOOL) parseCommandLineArguments;
-(BOOL) readSettingsPlist;
- (void)setActiveAppId:(NSString *)activeAppId;
-(BOOL) activeAppRequiresRefreshOnDrag;
-(BOOL) activeAppIsExcluded;
-(BOOL) activeAppRequiresMouseEventListener;
-(BOOL) activeAppRequiresTabletPointSubtype;
-(BOOL) getKeyboardConfiguration: (char *)keyboardConfiguration;
-(DeviceInfo *)getDeviceWithDeviceType:(device_type_t)deviceType andVendorID:(uint32_t)vendorID andProductID:(uint32_t)productID;
-(size_t) getNumberOfDevices;

@end
