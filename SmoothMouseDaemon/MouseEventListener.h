
#import <Foundation/Foundation.h>

#include <pthread.h>
#include <mach/mach_time.h>

@interface MouseEventListener : NSObject {
@private
    pthread_t threadId;
    NSRunLoop *runLoop;
}
-(void) start;
-(void) stop;
@end
