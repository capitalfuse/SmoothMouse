#pragma once

#import <IOKit/IODataQueueClient.h>

#import "MouseSupervisor.h"
#import "SystemMouseAcceleration.h"
#import "OverlayWindow.h"
#import "MouseEventListener.h"
#import "InterruptListener.h"

@interface Daemon : NSObject {
@private
    InterruptListener *interruptListener;
    MouseEventListener *mouseEventListener;
    OverlayWindow *overlay;
    SystemMouseAcceleration *accel;
    id globalMouseMonitor;
    BOOL connected;
    pthread_t mouseEventThreadID;
    io_service_t service;
    io_connect_t connect;
    IODataQueueMemory *queueMappedMemory;
    mach_port_t	recvPort;
    uint32_t dataSize;
    uint64_t eventsSinceStart;
    time_t startTime;
#if !__LP64__ || defined(IOCONNECT_MAPMEMORY_10_6)
    vm_address_t address;
    vm_size_t size;
#else
    mach_vm_address_t address;
    mach_vm_size_t size;
#endif
}

-(id) init;
+(id) instance;
-(void) destroy;
-(BOOL) loadDriver;
-(BOOL) connectToDriver;
-(BOOL) configureDriver;
-(BOOL) disconnectFromKext;
-(BOOL) isActive;
-(BOOL) isMouseEventListenerActive;
-(void) redrawOverlay;
-(void) say:(NSString *)message;
-(void) dumpState;

@end

extern Daemon *sDaemonInstance;
