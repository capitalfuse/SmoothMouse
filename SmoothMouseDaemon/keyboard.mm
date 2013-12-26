
#include "keyboard.h"

#include "Debug.h"

void keyboard_process_kext_event(keyboard_event_t *event) {
    LOG(@"key: %d", event->key);
}
