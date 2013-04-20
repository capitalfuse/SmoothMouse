#import <Foundation/Foundation.h>

#include <list>

#import "driver.h"

@interface DriverEventLog : NSObject {
    std::list<driver_event_t *> events;
}

-(void)add:(driver_event_t *)event;
-(BOOL)get:(driver_event_t *)event;
@end

extern DriverEventLog *sDriverEventLog;
