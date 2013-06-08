
#import <Foundation/Foundation.h>

#include <pthread.h>
#include <mach/mach_time.h>

@interface MouseEventListener : NSObject {
@private
    bool running;
    CFMachPortRef eventTap;
    CFRunLoopSourceRef runLoopSource;
}
-(void) start:(NSRunLoop *)runLoop;
-(void) stop:(NSRunLoop *)runLoop;
-(bool) isRunning;
@end
