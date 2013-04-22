
#import <Foundation/Foundation.h>

@interface Prio : NSObject {
}

// minimum value for computation seems to be 50000 mach units, and constraint must be >= computation
+(BOOL) setRealtimePrio: (NSString *)threadName withComputation:(int)computation withConstraint:(int)constraint;

@end
