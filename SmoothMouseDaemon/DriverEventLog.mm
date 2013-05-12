#import "DriverEventLog.h"

DriverEventLog *sDriverEventLog;

static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;

@implementation DriverEventLog

-(void)add:(driver_event_t *)event {
    pthread_mutex_lock(&mutex);
    driver_event_t *event_copy = (driver_event_t *)malloc(sizeof(driver_event_t));
    *event_copy = *event;
    events.push_back(event_copy);
    pthread_mutex_unlock(&mutex);
}

-(BOOL)get:(driver_event_t *)event {
    pthread_mutex_lock(&mutex);
    if (events.empty()) {
        pthread_mutex_unlock(&mutex);
        return FALSE;
    }
    driver_event_t *eventInList = events.front();
    *event = *eventInList;
    free(eventInList);
    events.pop_front();
    pthread_mutex_unlock(&mutex);
    return TRUE;
}

@end
