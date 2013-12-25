#pragma once

#import <IOKit/IODataQueueClient.h>

@interface Kext : NSObject {
@private
    BOOL connected;
    pthread_t mouseEventThreadID;
    io_service_t service;
    io_connect_t connect;
    IODataQueueMemory *queueMappedMemory;
    mach_port_t	recvPort;
    uint32_t queueSize;
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
-(BOOL) connect;
-(BOOL) disconnect;
-(BOOL) isConnected;
-(uint64_t) numEvents;
@end

