#import "DriverEventLog.h"

DriverEventLog *sDriverEventLog;

@implementation DriverEventLog

-(void)add:(driver_event_t *)event {
    @synchronized(self) {
        driver_event_t *event_copy = (driver_event_t *)malloc(sizeof(driver_event_t));
        *event_copy = *event;
        events.push_back(event_copy);
    }
}

-(BOOL)get:(driver_event_t *)event {
    @synchronized(self) {
        if (events.empty()) {
            return FALSE;
        }
        driver_event_t *eventInList = events.front();
        *event = *eventInList;
        free(eventInList);
        events.pop_front();
        return TRUE;
    }
}

@end
