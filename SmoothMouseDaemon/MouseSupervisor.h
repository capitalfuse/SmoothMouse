
#import <Foundation/Foundation.h>

@interface MouseSupervisorEvent : NSObject {
    float x;
    float y;
}

@end

@interface MouseSupervisor : NSObject {
    NSMutableArray *events;
}

- (id)init;
- (void) pushMouseEvent: (int) deltaX : (int) deltaY;
- (BOOL) popMouseEvent: (int) deltaX : (int) deltaY;
- (int) numItems;

@end
