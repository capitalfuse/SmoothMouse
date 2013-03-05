
#include <IOKit/hidsystem/event_status_driver.h>
#include <IOKit/hidsystem/IOHIDParameter.h>
#include <IOKit/hidsystem/IOHIDLib.h>
#include <stdio.h>

#import <Foundation/Foundation.h>

#include "daemon.h"

extern BOOL is_debug;
static double savedMouseAcceleration = -1;
static double savedTrackpadAcceleration = -1;

void initializeSystemMouseSettings()
{
    NXEventHandle   handle;
    CFStringRef     key;
    kern_return_t   ret;
    double          oldValueMouse,
    newValueMouse,
    oldValueTrackpad,
    newValueTrackpad;
    double          resetValue = 0.0;
    
    handle = NXOpenEventStatus();

    if (mouse_enabled) {
        key = CFSTR(kIOHIDMouseAccelerationType);
        
        ret = IOHIDGetAccelerationWithKey(handle, key, &oldValueMouse);
        if (ret != KERN_SUCCESS) {
            NSLog(@"Failed to get '%@'", key);
            return;
        }
        
        if (oldValueMouse != resetValue) {
            ret = IOHIDSetAccelerationWithKey(handle, key, resetValue);
            if (ret != KERN_SUCCESS) {
                NSLog(@"Failed to disable acceleration for '%@'", key);
            }
            
            if (savedMouseAcceleration == -1) {
                savedMouseAcceleration = oldValueMouse;
            }

            ret = IOHIDGetAccelerationWithKey(handle, key, &newValueMouse);
            if (ret != KERN_SUCCESS) {
                NSLog(@"Failed to get '%@' (2)", key);
                return;
            }
            
            NSLog(@"System mouse settings initialized (%f/%f)", oldValueMouse, newValueMouse);
        }
        //else if (is_debug) {
        //    NSLog(@"Skipped settings for '%@'", key);
        //}
    }
    
    if (trackpad_enabled) {
        key = CFSTR(kIOHIDTrackpadAccelerationType);
        
        ret = IOHIDGetAccelerationWithKey(handle, key, &oldValueTrackpad);
        if (ret != KERN_SUCCESS) {
            NSLog(@"Failed to get '%@'", key);
            // trackpad is probably not available on this system
            NSLog(@"Disabling trackpad");
            trackpad_enabled = false;
            return;
        }
        
        if (oldValueTrackpad != resetValue) {
            ret = IOHIDSetAccelerationWithKey(handle, key, resetValue);
            if (ret != KERN_SUCCESS) {
                NSLog(@"Failed to disable acceleration for '%@'", key);
            }
            
            if (savedTrackpadAcceleration == -1) {
                savedTrackpadAcceleration = oldValueTrackpad;
            }
            
            ret = IOHIDGetAccelerationWithKey(handle, key, &newValueTrackpad);
            if (ret != KERN_SUCCESS) {
                NSLog(@"Failed to get '%@' (2)", key);
                return;
            }
            
            NSLog(@"System trackpad settings initialized (%f/%f)", oldValueTrackpad, newValueTrackpad);
        }
        //else if (is_debug) {
        //    NSLog(@"Skipped settings for '%@'", key);
        //}
    }
    
    NXCloseEventStatus(handle);
}

void restoreSystemMouseSettings()
{
    NXEventHandle   handle;
    CFStringRef     key;
    kern_return_t   ret;

    handle = NXOpenEventStatus();
    
    key = CFSTR(kIOHIDMouseAccelerationType);
    if (savedMouseAcceleration != -1) {
        ret = IOHIDSetAccelerationWithKey(handle, key, savedMouseAcceleration);
        if (ret != KERN_SUCCESS) {
            NSLog(@"Failed to restore acceleration for '%@'", key);
        }
        NSLog(@"System mouse settings restored to %f", savedMouseAcceleration);
    } else if (is_debug) {
        NSLog(@"No need to restore acceleration for '%@'", key);
    }

    key = CFSTR(kIOHIDTrackpadAccelerationType);
    if (savedTrackpadAcceleration != -1) {        
        ret = IOHIDSetAccelerationWithKey(handle, key, savedTrackpadAcceleration);
        if (ret != KERN_SUCCESS) {
            NSLog(@"Failed to restore acceleration for '%@'", key);
        }
        NSLog(@"System trackpad settings restored to %f", savedTrackpadAcceleration);
    } else if (is_debug) {
        NSLog(@"No need to restore acceleration for '%@'", key);
    }

    NXCloseEventStatus(handle);
}
