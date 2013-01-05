
#pragma once

#include "kextdaemon.h"

typedef enum AccelerationCurve_s {
    ACCELERATION_CURVE_LINEAR   = 0,
    ACCELERATION_CURVE_WINDOWS  = 1
} AccelerationCurve;

bool mouse_init();
void mouse_handle(mouse_event_t *event);
void mouse_post();
void mouse_cleanup();
