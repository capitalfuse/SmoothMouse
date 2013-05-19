
#import <Foundation/Foundation.h>

#include <pthread.h>
#include <mach/mach_time.h>

@interface MouseEventListener : NSObject {
@private
    pthread_t threadId;
    bool running;
    NSRunLoop *runLoop;
}
-(void) start;
-(void) stop;
-(bool) isRunning;
@end
