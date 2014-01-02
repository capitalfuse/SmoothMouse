#pragma once

#import <IOKit/IODataQueueClient.h>

#include "KextInterface.h"

@protocol Kext<NSObject>
- (void)connected;
- (void)disconnected;
- (void)threadStarted;
- (void)didReceiveEvent:(kext_event_t *)event;
@end

@interface Kext : NSObject {
@private
    id<Kext> delegate;
    BOOL connected;
    pthread_t mouseEventThreadID;
    io_service_t service;
    io_connect_t connect;
    IODataQueueMemory *queueMappedMemory;
    mach_port_t	recvPort;
    uint32_t queueSize;
    uint64_t eventsSinceStart;
#if !__LP64__ || defined(IOCONNECT_MAPMEMORY_10_6)
    vm_address_t address;
    vm_size_t size;
#else
    mach_vm_address_t address;
    mach_vm_size_t size;
#endif
}

-(id) init;
-(void) setDelegate: (id) delegate;
-(BOOL) connect;
-(BOOL) disconnect;
-(BOOL) isConnected;
-(uint64_t) numEvents; // NOTE: remove this later, seq in events is enough to track it
-(BOOL) kextMethodConfigureDevice:(device_configuration_t *)deviceConfiguration;
-(BOOL) kextMethodGetDeviceInformation: (device_information_t *)deviceInfo forDeviceWithDeviceType: (device_type_t) deviceType andVendorId: (uint32_t) vendorID andProductID: (uint32_t) productID;
@end

