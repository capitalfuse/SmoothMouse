#import <Foundation/Foundation.h>

@interface SystemMouseAcceleration : NSObject {
    double savedMouseAcceleration;
    double savedTrackpadAcceleration;
}

-(id) init;
-(void) reset;
-(void) restore;

@end
