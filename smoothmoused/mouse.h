
#pragma once

#include "kextdaemon.h"

bool mouse_init();
void mouse_handle(mouse_event_t *event, double velocity);
void mouse_cleanup();
