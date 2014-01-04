
#import <Foundation/Foundation.h>

@interface DaemonController : NSObject {

}

- (BOOL) stop;
- (BOOL) start;
- (BOOL) update;
- (BOOL) isRunning;

@end
