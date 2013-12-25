#pragma once

#import <IOKit/IODataQueueClient.h>

#import "MouseSupervisor.h"
#import "SystemMouseAcceleration.h"
#import "OverlayWindow.h"
#import "MouseEventListener.h"
#import "InterruptListener.h"
#import "Kext.h"

@interface Daemon : NSObject {
@private
    Kext *kext;
    NSRunLoop *runLoop;
    InterruptListener *interruptListener;
    MouseEventListener *mouseEventListener;
    OverlayWindow *overlay;
    SystemMouseAcceleration *accel;
    id globalMouseMonitor;
    time_t startTime;
}

-(id) init;
+(id) instance;
-(void) trapSignals;
-(void) destroy;
-(BOOL) isActive;
-(BOOL) isMouseEventListenerActive;
-(void) redrawOverlay;
-(void) say:(NSString *)message;
-(void) dumpState;

@end

extern Daemon *sDaemonInstance;
