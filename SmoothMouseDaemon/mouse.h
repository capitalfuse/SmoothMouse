
#pragma once

#import "MouseSupervisor.h"

#include "kextdaemon.h"

typedef enum AccelerationCurve_s {
    ACCELERATION_CURVE_LINEAR   = 0,
    ACCELERATION_CURVE_WINDOWS  = 1,
    ACCELERATION_CURVE_OSX      = 2
} AccelerationCurve;

typedef enum Driver_s {
    DRIVER_QUARTZ_OLD,
    DRIVER_QUARTZ,
    DRIVER_IOHID
} Driver;

bool mouse_init();
void mouse_handle(mouse_event_t *event);
void mouse_cleanup();
void mouse_refresh();
void mouse_update_clicktime();
