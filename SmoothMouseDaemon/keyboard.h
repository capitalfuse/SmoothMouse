
#pragma once

#include "../KextProtocol.h"

//BOOL keyboard_init();
//BOOL keyboard_cleanup();
void keyboard_process_kext_event(keyboard_event_t *event);
