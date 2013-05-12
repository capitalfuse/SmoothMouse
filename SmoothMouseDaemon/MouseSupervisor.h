
#import <Foundation/Foundation.h>

#include <queue>

@interface MouseSupervisor : NSObject {
    std::queue<int> moveEvents;
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
