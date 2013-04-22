
#import <Foundation/Foundation.h>

#include <list>

#include <pthread.h>

@interface InterruptListener : NSObject {
@private
    pthread_t threadId;
    NSRunLoop *runLoop;
    BOOL running;
    std::list<uint64_t> events;
}
-(void) start;
-(void) stop;
-(BOOL) get:(uint64_t *) timestamp;
-(void) put:(uint64_t) timestamp;
-(int) numEvents;
@end

extern InterruptListener *sInterruptListener;
