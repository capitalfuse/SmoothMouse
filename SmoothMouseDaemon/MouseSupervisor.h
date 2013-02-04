//
//  MouseSupervisor.h
//  SmoothMouse
//
//  Created by Daniel Åkerud on 2/4/13.
//
//

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
