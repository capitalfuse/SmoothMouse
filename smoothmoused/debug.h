
#pragma once

#include "kextdaemon.h"

void debug_log_old(mouse_event_t *event, CGPoint currentPos, float calcx, float calcy);
void debug_register_event(mouse_event_t *event);
void debug_end();
