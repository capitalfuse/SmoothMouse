#pragma once

#import "MouseSupervisor.h"

#import <IOKit/IODataQueueClient.h>

extern BOOL is_debug;
extern BOOL is_memory;
extern BOOL is_timings;
extern BOOL is_dumping;
extern BOOL mouse_enabled;
extern BOOL trackpad_enabled;

extern MouseSupervisor *sMouseSupervisor;

@interface Daemon : NSObject {
@private
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

-(id)init;
-(oneway void) release;
-(void) handleGlobalMouseMovedEvent:(NSEvent *) event;
-(BOOL) loadSettings;
-(BOOL) loadDriver;
-(BOOL) connectToDriver;
-(BOOL) configureDriver;
-(BOOL) disconnectFromDriver;
-(BOOL) isActive;

@end

extern Daemon *sDaemonInstance;
