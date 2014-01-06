
#import "Kext.h"

#import <IOKit/IODataQueueClient.h>
#import <IOKit/kext/KextManager.h>
#import <mach/mach.h>
#include <pthread.h>
#include <string.h>

#import "Prio.h"
#include "KextInterface.h"
#include "Debug.h"

@implementation Kext

-(id)init
{
    eventsSinceStart = 0;
    connected = NO;

    self = [super init];

    return self;
}

-(void) setDelegate:(id)delegate_
{
    delegate = delegate_;
}

static void *KernelEventThread(void *instance)
{
    Kext *self = (__bridge Kext *) instance;

    //NSLog(@"KernelEventThread: Start (self: %p)", self);

    char *buf = (char *)malloc(self->queueSize);
    if (!buf) {
        NSLog(@"malloc error");
        return NULL;
    }

    if([self->delegate respondsToSelector:@selector(threadStarted)]) {
        [self->delegate threadStarted];
    }

    static int counter = 0;
    while (IODataQueueWaitForAvailableData(self->queueMappedMemory, self->recvPort) == kIOReturnSuccess) {
        int numPackets = 0;
        while (IODataQueueDataAvailable(self->queueMappedMemory)) {
            numPackets++;
            counter++;
            kern_return_t error = IODataQueueDequeue(self->queueMappedMemory, buf, &(self->queueSize));

            if (error) {
                NSLog(@"IODataQueueDequeue() failed");
                exit(0);
            }

            kext_event_t *kext_event = (kext_event_t *) buf;

            if([self->delegate respondsToSelector:@selector(didReceiveEvent:)]) {
                [self->delegate didReceiveEvent:kext_event];
            }
        }
    }

    free(buf);

    //NSLog(@"KernelEventThread: End");

    return NULL;
}

-(BOOL) connect
{
    @synchronized(self) {
        if (!connected) {
            kern_return_t error;

            service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("com_cyberic_SmoothMouse2"));
            if (service == IO_OBJECT_NULL) {
                NSLog(@"IOServiceGetMatchingService() failed");
                goto error;
            }

            error = IOServiceOpen(service, mach_task_self(), 0, &connect);
            if (error) {
                NSLog(@"IOServiceOpen() failed (kext is busy)");
                IOObjectRelease(service);
                goto error;
            }

            IOObjectRelease(service);

            recvPort = IODataQueueAllocateNotificationPort();
            if (MACH_PORT_NULL == recvPort) {
                NSLog(@"IODataQueueAllocateNotificationPort returned a NULL mach_port_t\n");
                goto error;
            }

            error = IOConnectSetNotificationPort(connect, kIODefaultMemoryType, recvPort, 0);
            if (kIOReturnSuccess != error) {
                NSLog(@"IOConnectSetNotificationPort returned %d\n", error);
                goto error;
            }

            error = IOConnectMapMemory(connect, kIODefaultMemoryType, mach_task_self(), &address, &size, kIOMapAnywhere);
            if (kIOReturnSuccess != error) {
                NSLog(@"IOConnectMapMemory returned %d\n", error);
                goto error;
            }

            queueMappedMemory = (IODataQueueMemory *) address;
            queueSize = (uint32_t) size;

            BOOL ok = [self kextMethodConnectToUserClient];
            if (!ok) {
                NSLog(@"Failed to connect to user client");
                goto error;
            }

            int threadError = pthread_create(&mouseEventThreadID, NULL, &KernelEventThread, (__bridge void *)self);
            if (threadError != 0)
            {
                NSLog(@"Failed to start mouse event thread");
                goto error;
            }

            if([delegate respondsToSelector:@selector(connected)]) {
                [delegate connected];
            }

            connected = YES;
        }

        return YES;
    error:
        return NO;
    }
}

-(BOOL) disconnect
{
    @synchronized(self) {
        if (connected) {

            connected = NO;

            if (recvPort) {
                mach_port_destroy(mach_task_self(), recvPort);
            }

            int rv = pthread_join(mouseEventThreadID, NULL);
            if (rv != 0) {
                NSLog(@"Failed to wait for kernel event thread");
            }

            if (address) {
                IOConnectUnmapMemory(connect, kIODefaultMemoryType, mach_task_self(), address);
            }

            if (connect) {
                IOServiceClose(connect);
            }

            //NSLog(@"Disconnected from KEXT");

            if([delegate respondsToSelector:@selector(disconnected)]) {
                [delegate disconnected];
            }

        }

        return YES;
    }
}

-(BOOL) isConnected
{
    @synchronized(self) {
        return connected;
    }
}

-(uint64_t) numEvents
{
    return eventsSinceStart;
}

-(BOOL) kextMethodConnectToUserClient
{
    kern_return_t	kernResult;

    kernResult = IOConnectCallScalarMethod(connect, KEXT_METHOD_CONNECT, NULL, 0, NULL, NULL);

    if (kernResult == KERN_SUCCESS) {
        return YES;
    } else {
        return NO;
    }
}

-(BOOL) kextMethodConfigureDevice:(device_configuration_t *)deviceConfiguration {
    kern_return_t	kernResult;

    kernResult = IOConnectCallStructMethod(connect, KEXT_METHOD_CONFIGURE_DEVICE,  deviceConfiguration,
                                           sizeof(device_configuration_t), NULL, NULL);

    if (kernResult == KERN_SUCCESS) {
        return YES;
    } else {
        return NO;
    }
}

-(BOOL) kextMethodGetDeviceInformation: (device_information_t *)deviceInfo forDeviceWithDeviceType: (device_type_t) deviceType andVendorId: (uint32_t) vendorID andProductID: (uint32_t) productID
{
    kern_return_t	kernResult;
    uint64_t scalarI_64[3];

    scalarI_64[0] = deviceType;
    scalarI_64[1] = vendorID;
    scalarI_64[2] = productID;

    size_t device_info_size = sizeof(device_information_t);
    kernResult = IOConnectCallMethod(connect, KEXT_METHOD_GET_DEVICE_INFORMATION, scalarI_64, 3, NULL,
                                     0, NULL, 0, deviceInfo, &device_info_size);

    if (kernResult == KERN_SUCCESS) {
        LOG(@"KEXT DEVICE INFO: %d:%d trackpad: %d", deviceInfo->vendor_id, deviceInfo->product_id, deviceInfo->pointing.is_trackpad);
        return YES;
    } else {
        return NO;
    }
}

@end
