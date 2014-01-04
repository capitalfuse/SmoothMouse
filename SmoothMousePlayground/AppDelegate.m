
#import "AppDelegate.h"

#import "Debug.h"
#import "constants.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    BOOL ok;

    configuration = [[Configuration alloc] init];
    ok = [configuration load];

    if (!ok) {
        [configuration writeDefaultConfiguration];
    }

    kext = [[Kext alloc] init];
    [kext setDelegate:self];
    ok = [kext connect];

    if (!ok) {
        [self alertFailedToLoadKext];
        [NSApp close];
    }

    [_tableView reloadData];
    if ([_tableView numberOfRows] > 0) {
        NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:0];
        [_tableView selectRowIndexes:indexSet byExtendingSelection:NO];
    }
    [self refreshDeviceView];

    daemonController = [[DaemonController alloc] init];
}

/* === DEVICE VIEW ACTIONS === */

- (IBAction)enableToggled:(id)sender {
    LOG(@"enter");
    NSMutableDictionary *device = [self getSelectedDevice];
    if (device) {
        BOOL enabled = !![checkboxEnable state];
        [device setObject:[NSNumber numberWithBool:enabled] forKey:SETTINGS_ENABLED];
        [configuration save];
    }
    if ([configuration anyDeviceIsEnabled]) {
        [daemonController start];
    } else {
        [daemonController stop];
    }
}

- (IBAction)curveChanged:(id)sender {
    LOG(@"enter");
    NSMutableDictionary *device = [self getSelectedDevice];
    if (device) {
        NSInteger itemIndex = [curvePopup indexOfSelectedItem];
        NSString *curve = NULL;
        switch (itemIndex) {
            default: /* fall through to Off */
            case 0: curve = @"Off"; break;
            case 1: curve = @"Windows"; break;
            case 2: curve = @"OS X"; break;
        }
        [device setObject:curve forKey:SETTINGS_ACCELERATION_CURVE];
        [configuration save];
        [daemonController update];
    }
}

- (IBAction)velocityChanged:(id)sender {
    LOG(@"enter");
    NSMutableDictionary *device = [self getSelectedDevice];
    if (device) {
        double velocity = [velocitySlider doubleValue];
        [device setObject:[NSNumber numberWithDouble:velocity] forKey:SETTINGS_VELOCITY];
        [configuration save];
        [daemonController update];

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

            NSDictionary *device = [configuration getDeviceWithVendorID: kextDeviceInfo.vendor_id andProductID:kextDeviceInfo.product_id];

            if (!device) {
                [configuration createDeviceFromKextDeviceInformation:&kextDeviceInfo];
            }

            [configuration connectDeviceWithVendorID:kextDeviceInfo.vendor_id andProductID:kextDeviceInfo.product_id];

            [_tableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:NO];

            break;
        }
        case EVENT_TYPE_DEVICE_REMOVED:
        {
            device_removed_event_t *device_removed = &kext_event->device_removed;
            NSLog(@"DEVICE REMOVED, VendorID: %u, ProductID: %u",
                  device_removed->base.vendor_id, device_removed->base.product_id);

            [configuration disconnectDeviceWithVendorID:device_removed->base.vendor_id andProductID:device_removed->base.product_id];

            [_tableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:NO];

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

/* === TABLE VIEW NOTIFICATIONS === */

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    NSUInteger count = [[configuration getDevices] count];
    LOG(@"count: %lu", count);
    return count;
}

// This method is optional if you use bindings to provide the data
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    LOG(@"enter");
    NSMutableDictionary *device = [configuration getDeviceAtIndex:(int)row];
    NSString *identifier = [tableColumn identifier];
    if (device) {
        if ([identifier isEqualToString:SETTINGS_PRODUCT]) {
            NSTableCellView *view = [tableView makeViewWithIdentifier:identifier owner:self];
            view.textField.stringValue = [device objectForKey:SETTINGS_PRODUCT];
            return view;
        } else if ([identifier isEqualToString:SETTINGS_MANUFACTURER]) {
            NSTableCellView *view = [tableView makeViewWithIdentifier:identifier owner:self];
            view.textField.stringValue = [device objectForKey:SETTINGS_MANUFACTURER];
            return view;
        }
    }
    return nil;
}

- (IBAction)deviceSelected:(id)sender
{
    [self refreshDeviceView];
}

- (void) refreshDeviceView {
    NSMutableDictionary *device = [self getSelectedDevice];

    [deviceView setHidden:(device == nil)];

    if (device) {
        BOOL ok;

        BOOL enabled;
        ok = [Configuration getBoolInDictionary:device forKey:SETTINGS_ENABLED withResult:&enabled];
        if (!ok) {
            LOG(@"Key %@ missing in device", SETTINGS_ENABLED);
            [NSApp close];
        }

        NSString *curve;
        ok = [Configuration getStringInDictionary:device forKey:SETTINGS_ACCELERATION_CURVE withResult:&curve];
        if (!ok) {
            LOG(@"Key %@ missing in device", SETTINGS_ACCELERATION_CURVE);
            [NSApp close];
        }

        double velocity;
        ok = [Configuration getDoubleInDictionary:device forKey:SETTINGS_VELOCITY withResult:&velocity];
        if (!ok) {
            LOG(@"Key %@ missing in device", SETTINGS_VELOCITY);
            [NSApp close];
        }

        int curveIndex;
        ok = [self getIndexFromAccelerationCurveString:curve withResult:&curveIndex];
        if (!ok) {
            curveIndex = 0;
        }

        [checkboxEnable setState:enabled];
        [curvePopup selectItemAtIndex:curveIndex];
        [velocitySlider setDoubleValue:velocity];
    }
}

-(BOOL)getIndexFromAccelerationCurveString: (NSString *) string withResult: (int *)result
{
    if ([string compare:SETTINGS_CURVE_WINDOWS] == NSOrderedSame) {
        *result = 1;
        return YES;
    }

    if ([string compare:SETTINGS_CURVE_OSX] == NSOrderedSame) {
        *result = 2;
        return YES;
    }

    if ([string compare:SETTINGS_CURVE_OFF] == NSOrderedSame) {
        *result = 0;
        return YES;
    }

    return NO;
}

-(NSMutableDictionary *) getSelectedDevice
{
    NSInteger index = [_tableView selectedRow];
    NSMutableDictionary *device = [configuration getDeviceAtIndex:(int)index];
    return device;
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
