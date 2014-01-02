
#import "SmoothMousePrefs.h"

@implementation SmoothMousePrefs

- (void)mainViewDidLoad
{
    kext = [[Kext alloc] init];
    [kext setDelegate:self];
    BOOL ok = [kext connect];
    if (!ok) {
        [self alertFailedToLoadKext];
        [NSApp close];
    }
}

/* === KEXTPROTOCOL === */

- (void)connected {
}

- (void)disconnected {
}

- (void)threadStarted {
}

- (void)didReceiveEvent:(kext_event_t *)kext_event {
    //LOG(@"kext event: size %u, event type: %u, device_type: %d, timestamp: %llu", self->queueSize, kext_event->base.event_type, kext_event->base.device_type, kext_event->base.timestamp);

    switch (kext_event->base.event_type) {
        case EVENT_TYPE_DEVICE_ADDED:
        {
            device_added_event_t *device_added = &kext_event->device_added;
            device_information_t kextDeviceInfo;
            [kext kextMethodGetDeviceInformation: &kextDeviceInfo forDeviceWithDeviceType:device_added->base.device_type andVendorId: device_added->base.vendor_id andProductID: device_added->base.product_id];
            if (device_added->base.device_type == DEVICE_TYPE_POINTING) {
                NSLog(@"DEVICE ADDED (trackpad: %d), vendor_id: %u, product_id: %u", kextDeviceInfo.pointing.is_trackpad, kextDeviceInfo.vendor_id, kextDeviceInfo.product_id);
            }
            break;
        }
        case EVENT_TYPE_DEVICE_REMOVED:
        {
            device_removed_event_t *device_removed = &kext_event->device_removed;
            NSLog(@"DEVICE REMOVED, VendorID: %u, ProductID: %u",
                device_removed->base.vendor_id, device_removed->base.product_id);
            break;
        }
        case EVENT_TYPE_POINTING:
            break;
        case EVENT_TYPE_KEYBOARD:
            break;
        default:
            NSLog(@"Unknown event type: %d", kext_event->base.event_type);
            break;
    }
}

/* ===              === */

-(void) alertFailedToLoadKext {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Problem with installation!"];
    [alert setInformativeText:@"A vital part of SmoothMouse has not been correctly installed :-("];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
    [alert release];
}

@end
