
#import <Foundation/Foundation.h>

#import "mouse.h"
#import "driver.h"

@interface Config : NSObject {
    // from plist
    BOOL mouseEnabled;
    BOOL trackpadEnabled;
    double mouseVelocity;
    double trackpadVelocity;
    AccelerationCurve mouseCurve;
    AccelerationCurve trackpadCurve;
    Driver driver;

    // from command line
    BOOL debugEnabled;
    BOOL memoryLoggingEnabled;
    BOOL timingsEnabled;
    BOOL sendAuxEventsEnabled;
    NSString *activeAppBundleId;
    BOOL overlayEnabled;
    BOOL sayEnabled;
    BOOL latencyEnabled;

    NSArray *excludedApps;
}

@property BOOL mouseEnabled;
@property BOOL trackpadEnabled;
@property double mouseVelocity;
@property double trackpadVelocity;
@property AccelerationCurve mouseCurve;
@property AccelerationCurve trackpadCurve;
@property Driver driver;
@property BOOL debugEnabled;
@property BOOL memoryLoggingEnabled;
@property BOOL timingsEnabled;
@property BOOL sendAuxEventsEnabled;
@property (copy) NSString* activeAppBundleId;
@property BOOL overlayEnabled;
@property BOOL sayEnabled;
@property BOOL latencyEnabled;

+(Config *) instance;
-(id) init;
-(BOOL) parseCommandLineArguments;
-(BOOL) readSettingsPlist;
-(AccelerationCurve) getAccelerationCurveFromDict:(NSDictionary *)dictionary withKey:(NSString *)key;
-(BOOL) activeAppIsExcluded;
-(BOOL) appIsExcluded:(NSString *)app;

@end
