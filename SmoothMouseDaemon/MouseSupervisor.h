
#import <Foundation/Foundation.h>

@interface MouseMoveEvent : NSObject {
    float x;
    float y;
}

@end

@interface MouseSupervisor : NSObject {
    NSMutableArray *moveEvents;
    int clickEvents;
    int clickEventsZeroLevel;
}

- (id)init;
- (void) pushMoveEvent: (int) deltaX : (int) deltaY;
- (BOOL) popMoveEvent: (int) deltaX : (int) deltaY;
- (void) pushClickEvent;
- (void) popClickEvent;
- (int) numMoveEvents;
- (BOOL) hasClickEvents;
- (int) numClickEvents;
- (void) resetClickEvents;

@end

extern MouseSupervisor *sMouseSupervisor;
