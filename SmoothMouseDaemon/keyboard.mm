
#include "keyboard.h"

#include "Debug.h"

static CGEventSourceRef eventSource = NULL;

void keyboard_process_kext_event(keyboard_event_t *event) {
    LOG(@"key: %u, type: %u, repeat: %d, flags: %u", event->key, event->type, event->repeat, event->flags);
    if (eventSource == NULL) {
        eventSource = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
        if (eventSource == NULL) {
            NSLog(@"call to CGEventSourceSetKeyboardType failed");
            return;
        }
    }
    bool pressed = true;
    if (event->type == 11) {
        pressed = false;
    }
    LOG(@"Sending keypress, key: %d, pressed: %d", event->key, pressed);
    CGEventRef evt = CGEventCreateKeyboardEvent (NULL, (CGKeyCode)event->key, pressed);
    CGEventPost(kCGSessionEventTap, evt);
    CFRelease(evt);
}
