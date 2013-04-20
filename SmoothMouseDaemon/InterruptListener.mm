
#import "InterruptListener.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOMessage.h>
#include <IOKit/hid/IOHIDLib.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <IOKit/hid/IOHIDUsageTables.h>
#include <IOKit/hidsystem/IOHIDLib.h>
#include <IOKit/hidsystem/IOHIDShared.h>
#include <IOKit/hidsystem/IOHIDParameter.h>
#include <ApplicationServices/ApplicationServices.h>
#include <mach/mach_time.h>
#include <pthread.h>

#import "debug.h"
#include "mach_timebase_util.h"
#import "Prio.h"

/* */
static IONotificationPortRef gNotifyPort = NULL;
static io_iterator_t gAddedIter = 0;
//static CGPoint point0 = {0, 0};
static char first_interrupt = 1;

/* */
typedef enum CalibrationState {
    kCalibrationStateInactive = 0,
    kCalibrationStateTopLeft,
    kCalibrationStateTopRight,
    kCalibrationStateBottomRight,
    kCalibrationStateBottomLeft
} CalibrationState;

typedef struct HIDData {
    io_object_t	notification;
    IOHIDDeviceInterface122 **hidDeviceInterface;
    IOHIDQueueInterface **hidQueueInterface;
    CFDictionaryRef hidElementDictionary;
    CFRunLoopSourceRef eventSource;
    CalibrationState state;
    SInt32 minx;
    SInt32 maxx;
    SInt32 miny;
    SInt32 maxy;
    UInt8 buffer[256];
} HIDData;

typedef HIDData* HIDDataRef;

typedef struct HIDElement {
    SInt32 currentValue;
    SInt32 usagePage;
    SInt32 usage;
    IOHIDElementType type;
    IOHIDElementCookie cookie;
    HIDDataRef owner;
}HIDElement;

typedef HIDElement* HIDElementRef;

/* */
static void find_device ();
static void init_device (void *refCon, io_iterator_t iterator);
static void device_release (void *refCon, io_service_t service,
							natural_t messageType, void *messageArgument);
static void interrupt_callback (void *target, IOReturn result, void *refcon,
								void *sender, uint32_t bufferSize);



InterruptListener *sInterruptListener;

@implementation InterruptListener

static void *InterruptListenerThread(void *instance)
{
    LOG(@"InterruptListenerThread: Start");

    InterruptListener *self = (InterruptListener *) instance;
    sInterruptListener = self;

    self->runLoop = [NSRunLoop currentRunLoop];

    [Prio setRealtimePrio:@"InterruptThread"];

    find_device();

    NSDate *date = [NSDate distantFuture];

    while (self->running && [self->runLoop runMode:NSDefaultRunLoopMode beforeDate:date]);

    LOG(@"InterruptListenerThread: End");

    return NULL;
}

-(void) start {
    LOG(@"InterruptListener::start");
    running = 1;
    int err = pthread_create(&threadId, NULL, &InterruptListenerThread, self);
    if (err != 0) {
        NSLog(@"Failed to start InterruptListenerThread");
        running = 0;
    }
}

-(void) stop {
    LOG(@"InterruptListener::stop");
    running = 0;

    [runLoop performSelector: @selector(stopThread:) target:self argument:nil order:0 modes:[NSArray arrayWithObject:NSDefaultRunLoopMode]];

    // need to wake up after posting a selector to the runloop:
    // http://www.cocoabuilder.com/archive/cocoa/228634-nsrunloop-performselector-needs-cfrunloopwakeup.html
    CFRunLoopRef crf = [runLoop getCFRunLoop];
    CFRunLoopWakeUp(crf);

    int rv = pthread_join(threadId, NULL);
    if (rv != 0) {
        NSLog(@"Failed to wait for InterruptListenerThread");
    }
}

-(void) stopThread: (id) argument {
    LOG(@"InterruptListener::stopThread");
    CFRunLoopStop([[NSRunLoop currentRunLoop] getCFRunLoop]);
}

-(void) put:(uint64_t) timestamp {
    @synchronized(self) {
        events.push_back(timestamp);
        //LOG(@"INTERRUPT: ADDED TIMESTAMP %llu (%d items now)", timestamp, (int)events.size());
    }
}

-(BOOL) get:(uint64_t *) timestamp {
    @synchronized(self) {
        if (events.empty()) {
            return NO;
        }
        *timestamp = events.front();
        events.pop_front();
        //LOG(@"INTERRUPT: POPPED TIMESTAMP %llu (%d items left)", *timestamp, (int)events.size());
        return YES;
    }
}

@end













void find_device () {
    CFMutableDictionaryRef matchingDict;
    CFNumberRef refUsage;
    CFNumberRef refUsagePageKey;
    SInt32 usage = 1;        /* mouse */
    SInt32 usagePageKey = 2; /* mouse */
    mach_port_t	masterPort;
    kern_return_t kr;

    kr = IOMasterPort (bootstrap_port, &masterPort);
    if (kr || !masterPort) {
        return;
	}

    gNotifyPort = IONotificationPortCreate (masterPort);
    CFRunLoopAddSource (CFRunLoopGetCurrent (), IONotificationPortGetRunLoopSource (gNotifyPort), kCFRunLoopDefaultMode);

    matchingDict = IOServiceMatching ("IOHIDDevice");

    if (!matchingDict) {
		return;
	}

    refUsage = CFNumberCreate (kCFAllocatorDefault, kCFNumberIntType, &usage);
    refUsagePageKey = CFNumberCreate (kCFAllocatorDefault, kCFNumberIntType, &usagePageKey);

    CFDictionarySetValue (matchingDict, CFSTR (kIOHIDPrimaryUsageKey), refUsagePageKey);
    CFDictionarySetValue (matchingDict, CFSTR (kIOHIDPrimaryUsagePageKey), refUsage);

    CFRelease (refUsage);
    CFRelease (refUsagePageKey);

    kr = IOServiceAddMatchingNotification (gNotifyPort, kIOFirstMatchNotification, matchingDict, init_device, NULL, &gAddedIter);

    if (kr != kIOReturnSuccess) {
        return;
	}

    init_device (NULL, gAddedIter);
}

void init_device (void *refCon, io_iterator_t iterator) {
    io_object_t hidDevice = 0;
    IOCFPlugInInterface **plugInInterface = NULL;
    IOHIDDeviceInterface122 **hidDeviceInterface = NULL;
    HRESULT result = S_FALSE;
    HIDDataRef hidDataRef = NULL;
    IOReturn kr;
    SInt32 score;

    while ((hidDevice = IOIteratorNext (iterator))) {
        kr = IOCreatePlugInInterfaceForService (hidDevice,
												kIOHIDDeviceUserClientTypeID,
												kIOCFPlugInInterfaceID,
												&plugInInterface, &score);

        if (kr != kIOReturnSuccess) {
            goto HIDDEVICEADDED_NONPLUGIN_CLEANUP;
		}

        result = (*plugInInterface)->QueryInterface (plugInInterface,
													 CFUUIDGetUUIDBytes
													 (kIOHIDDeviceInterfaceID),
													 (LPVOID *)&hidDeviceInterface);

        if ((result == S_OK) && hidDeviceInterface) {
            hidDataRef = (HIDDataRef) malloc (sizeof (HIDData));
            bzero (hidDataRef, sizeof (HIDData));

            hidDataRef->hidDeviceInterface = hidDeviceInterface;

            result = (*(hidDeviceInterface))->open
			(hidDataRef->hidDeviceInterface, 0);
            result = (*(hidDeviceInterface))->createAsyncEventSource
			(hidDataRef->hidDeviceInterface, &hidDataRef->eventSource);
            result = (*(hidDeviceInterface))->setInterruptReportHandlerCallback
			(hidDataRef->hidDeviceInterface, hidDataRef->buffer,
			 sizeof(hidDataRef->buffer), &interrupt_callback, NULL,
			 hidDataRef);

            CFRunLoopAddSource (CFRunLoopGetCurrent (), hidDataRef->eventSource,
								kCFRunLoopDefaultMode);

            IOServiceAddInterestNotification (gNotifyPort, hidDevice,
											  kIOGeneralInterest,
											  device_release, hidDataRef,
											  &(hidDataRef->notification));

            goto HIDDEVICEADDED_CLEANUP;
        }

        if (hidDeviceInterface) {
            (*hidDeviceInterface)->Release(hidDeviceInterface);
            hidDeviceInterface = NULL;
        }

        if (hidDataRef) {
            free ( hidDataRef );
		}

	HIDDEVICEADDED_CLEANUP:
        (*plugInInterface)->Release(plugInInterface);

	HIDDEVICEADDED_NONPLUGIN_CLEANUP:
        IOObjectRelease(hidDevice);
    }
}

void device_release (void *refCon, io_service_t service, natural_t messageType,
					 void *messageArgument) {
    kern_return_t kr;
    HIDDataRef hidDataRef = (HIDDataRef) refCon;

    if ((hidDataRef != NULL) && (messageType == kIOMessageServiceIsTerminated)) {
        if (hidDataRef->hidQueueInterface != NULL) {
            kr = (*(hidDataRef->hidQueueInterface))->stop
			((hidDataRef->hidQueueInterface));
            kr = (*(hidDataRef->hidQueueInterface))->dispose
			((hidDataRef->hidQueueInterface));
            kr = (*(hidDataRef->hidQueueInterface))->Release
			(hidDataRef->hidQueueInterface);
            hidDataRef->hidQueueInterface = NULL;
        }

        if (hidDataRef->hidDeviceInterface != NULL) {
            kr = (*(hidDataRef->hidDeviceInterface))->close
			(hidDataRef->hidDeviceInterface);
            kr = (*(hidDataRef->hidDeviceInterface))->Release
			(hidDataRef->hidDeviceInterface);
            hidDataRef->hidDeviceInterface = NULL;
        }

        if (hidDataRef->notification) {
            kr = IOObjectRelease(hidDataRef->notification);
            hidDataRef->notification = 0;
        }
    }
}

void interrupt_callback (void *target, IOReturn result, void *refcon,
						 void *sender, uint32_t bufferSize) {
    HIDDataRef hidDataRef = (HIDDataRef) refcon;
#if 0
	char hw_x, hw_y; /* hardware coordinates received from mouse */
    CGEventRef event;
	CGPoint point;
	int sw_x, sw_y; /* softwwutare coordinates */
#endif

	if ( !hidDataRef )
        return;
	if (bufferSize < 4)
		return;

    mach_timebase_info_data_t info;
    mach_timebase_info(&info);

    uint64_t timestamp = mach_absolute_time();
    [sInterruptListener put:timestamp];

#if 0
	hw_x = (char) hidDataRef->buffer[1];
	hw_y = (char) hidDataRef->buffer[2];

	event = CGEventCreate (NULL);
	point = CGEventGetLocation(event);

	sw_x = point.x - point0.x;
	sw_y = point.y - point0.y;

/*    for (int i = 0; i < bufferSize; i++) {
        printf("%02X ", hidDataRef->buffer[i]);
    } */

    if (!first_interrupt) {
        LOG(@"Mouse Interrupt: hw: %3i x %3i sw: %3i x %3i, timestamp %llu, size %d:",
            hw_x, hw_y, sw_x, sw_y,
            convert_from_mach_timebase_to_nanos(timestamp, &info),
            bufferSize);
    } else {
        LOG(@"Mouse Interrupt: hw: %3i x %3i sw:   ? x   ?, timestamp %llu, size %d:",
            hw_x, hw_y,
            convert_from_mach_timebase_to_nanos(timestamp, &info),
            bufferSize);
    }

	point0.x = point.x;
	point0.y = point.y;
#endif

    first_interrupt = 0;
}