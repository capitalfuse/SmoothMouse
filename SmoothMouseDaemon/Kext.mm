
#import "Kext.h"

#import <IOKit/IODataQueueClient.h>
#import <IOKit/kext/KextManager.h>
#import <mach/mach.h>
#include <pthread.h>
#include <string.h>

#import "Prio.h"
#include "KextProtocol.h"
#include "debug.h"
#include "mouse.h"
#include "keyboard.h"

double start, end, e1, e2, mhs, mhe, outerstart, outerend, outersum = 0, outernum = 0;

@implementation Kext

-(id)init
{
    eventsSinceStart = 0;
    connected = NO;

    self = [super init];

    return self;
}

static void *KernelEventThread(void *instance)
{
    Kext *self = (Kext *) instance;

    //NSLog(@"KernelEventThread: Start");

    kern_return_t error;

    char *buf = (char *)malloc(self->queueSize);
    if (!buf) {
        NSLog(@"malloc error");
        return NULL;
    }

    [Prio setRealtimePrio: @"KernelEventThread" withComputation:20000 withConstraint:50000];

    (void) mouse_init();

    Config *config = [Config instance];

    static int counter = 0;
    while (IODataQueueWaitForAvailableData(self->queueMappedMemory, self->recvPort) == kIOReturnSuccess) {
        outerend = GET_TIME();
        int numPackets = 0;
        while (IODataQueueDataAvailable(self->queueMappedMemory)) {
            start = GET_TIME();
            numPackets++;
            counter++;
            error = IODataQueueDequeue(self->queueMappedMemory, buf, &(self->queueSize));
            kext_event_t *kext_event = (kext_event_t *) buf;

            if (error) {
                LOG(@"IODataQueueDequeue() failed");
                exit(0);
            }

            LOG(@"kext event: size %u, event type: %u, device_type: %d, timestamp: %llu", self->queueSize, kext_event->base.event_type, kext_event->base.device_type, kext_event->base.timestamp);

            mhs = GET_TIME();

            switch (kext_event->base.event_type) {
                case EVENT_TYPE_DEVICE_ADDED:
                {
                    device_added_event_t *device_added = &kext_event->device_added;
                    device_information_t deviceInfo;
                    [self kextMethodGetDeviceInformation: &deviceInfo forDeviceWithDeviceType:device_added->base.device_type andVendorId: device_added->base.vendor_id andProductID: device_added->base.product_id];
                    LOG(@"DEVICE ADDED, vendor_id: %u, product_id: %u, manufacturer string: '%s', product string: '%s'",
                        device_added->base.vendor_id, device_added->base.product_id, deviceInfo.manufacturer_string, deviceInfo.product_string);
                    if (device_added->base.device_type == DEVICE_TYPE_POINTING) {
                        if (([config trackpadEnabled] && deviceInfo.pointing.is_trackpad) ||
                            ([config mouseEnabled] && !deviceInfo.pointing.is_trackpad)) {
                            device_configuration_t config;
                            memset(&config, 0, sizeof(device_configuration_t));
                            config.device_type = DEVICE_TYPE_POINTING;
                            config.vendor_id = device_added->base.vendor_id;
                            config.product_id = device_added->base.product_id;
                            config.enabled = 1;
                            [self kextMethodConfigureDevice:&config];
                            LOG(@"ENABLED POINTING DEVICE (trackpad: %d), vendor_id: %u, product_id: %u", deviceInfo.pointing.is_trackpad, deviceInfo.vendor_id, deviceInfo.product_id);
                        }
                    } else if (device_added->base.device_type == DEVICE_TYPE_KEYBOARD) {
                        if ([config keyboardEnabled]) {
                            device_configuration_t config;
                            memset(&config, 0, sizeof(device_configuration_t));
                            config.device_type = DEVICE_TYPE_KEYBOARD;
                            config.vendor_id = device_added->base.vendor_id;
                            config.product_id = device_added->base.product_id;
                            config.enabled = 1;
                            [self kextMethodConfigureDevice:&config];
                            LOG(@"ENABLED KEYBOARD DEVICE (trackpad: %d), vendor_id: %u, product_id: %u", deviceInfo.pointing.is_trackpad, deviceInfo.vendor_id, deviceInfo.product_id);
                        }
                    }
                    break;
                }
                case EVENT_TYPE_DEVICE_REMOVED:
                {
                    device_removed_event_t *device_removed = &kext_event->device_removed;
                    device_information_t deviceInfo;
                    [self kextMethodGetDeviceInformation: &deviceInfo forDeviceWithDeviceType: device_removed->base.device_type andVendorId: device_removed->base.vendor_id andProductID: device_removed->base.product_id];
                    LOG(@"DEVICE REMOVED, vendor_id: %u, product_id: %u, manufacturer string: '%s', product string: '%s'",
                        device_removed->base.vendor_id, device_removed->base.product_id, deviceInfo.manufacturer_string, deviceInfo.product_string);
                    break;
                }
                case EVENT_TYPE_POINTING:
                    LOG(@"EVENT_TYPE_POINTING");
                    mouse_process_kext_event(&kext_event->pointing);
                    break;
                case EVENT_TYPE_KEYBOARD:
                    LOG(@"EVENT_TYPE_KEYBOARD");
                    keyboard_process_kext_event(&kext_event->keyboard);
                    break;
                default:
                    LOG(@"Unknown event type: %d", kext_event->base.event_type);
                    break;
            }

            if ([[Config instance] debugEnabled]) {
                debug_register_event(kext_event);
            }
            self->eventsSinceStart++;
            mhe = GET_TIME();
            end = GET_TIME();
            if ([[Config instance] timingsEnabled]) {
                LOG(@"timings: outer: %f, inner: %f, process mouse event: %f, seqnum: %llu, burst: %d, coalesced: %d", outerend-outerstart, end-start, mhe-mhs, kext_event->base.seq, numPackets, numCoalescedEvents);
            }
        }

        if (outerstart != 0 && outerend != 0) {
            outernum += 1;
            outersum += (outerend-outerstart);
        }

        outerstart = GET_TIME();
    }

    (void) mouse_cleanup();

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

            int threadError = pthread_create(&mouseEventThreadID, NULL, &KernelEventThread, self);
            if (threadError != 0)
            {
                NSLog(@"Failed to start mouse event thread");
                goto error;
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

            NSLog(@"Disconnected from KEXT");
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
        return YES;
    } else {
        return NO;
    }
}

@end
