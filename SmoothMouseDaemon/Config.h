
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

+(Config *) instance;
-(id) init;
-(BOOL) parseCommandLineArguments;
-(BOOL) readSettingsPlist;
-(AccelerationCurve) getAccelerationCurveFromDict:(NSDictionary *)dictionary withKey:(NSString *)key;

@end
