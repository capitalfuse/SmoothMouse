#pragma once

#import <IOKit/IODataQueueClient.h>

#import "MouseSupervisor.h"
#import "SystemMouseAcceleration.h"

extern MouseSupervisor *sMouseSupervisor;

@interface Daemon : NSObject {
@private
    SystemMouseAcceleration *accel;
    id globalMouseMonitor;
    BOOL connected;
    pthread_t mouseEventThreadID;
    io_service_t service;
	io_connect_t connect;
	IODataQueueMemory *queueMappedMemory;
	mach_port_t	recvPort;
	uint32_t dataSize;
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
-(void) handleGlobalMouseMovedEvent:(NSEvent *) event;
-(BOOL) loadDriver;
-(BOOL) connectToDriver;
-(BOOL) configureDriver;
-(BOOL) disconnectFromKext;
-(BOOL) isActive;

@end

extern Daemon *sDaemonInstance;
