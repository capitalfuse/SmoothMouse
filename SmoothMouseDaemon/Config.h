
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
    BOOL forceDragRefreshEnabled;

    // from command line
    BOOL debugEnabled;
    BOOL memoryLoggingEnabled;
    BOOL timingsEnabled;
    BOOL sendAuxEventsEnabled;
    BOOL overlayEnabled;
    BOOL sayEnabled;
    BOOL latencyEnabled;

    BOOL activeAppRequiresConstantRefresh;
    BOOL activeAppRequiresRefreshOnDrag;
    BOOL activeAppIsExcluded;
    BOOL activeAppRequiresMouseEventListener;
    BOOL activeAppRequiresTabletPointSubtype;

    NSArray *excludedApps;
}

@property BOOL mouseEnabled;
@property BOOL trackpadEnabled;
@property double mouseVelocity;
@property double trackpadVelocity;
@property AccelerationCurve mouseCurve;
@property AccelerationCurve trackpadCurve;
@property Driver driver;
@property BOOL forceDragRefreshEnabled;
@property BOOL debugEnabled;
@property BOOL memoryLoggingEnabled;
@property BOOL timingsEnabled;
@property BOOL sendAuxEventsEnabled;
@property BOOL overlayEnabled;
@property BOOL sayEnabled;
@property BOOL latencyEnabled;

+(Config *) instance;
-(id) init;
-(BOOL) parseCommandLineArguments;
-(BOOL) readSettingsPlist;
-(AccelerationCurve) getAccelerationCurveFromDict:(NSDictionary *)dictionary withKey:(NSString *)key;
- (void)setActiveAppId:(NSString *)activeAppId;
-(BOOL) activeAppRequiresConstantRefresh;
-(BOOL) activeAppRequiresRefreshOnDrag;
-(BOOL) activeAppIsExcluded;
-(BOOL) activeAppRequiresMouseEventListener;
-(BOOL) activeAppRequiresTabletPointSubtype;

@end
