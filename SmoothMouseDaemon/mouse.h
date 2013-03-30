
#pragma once

#import "MouseSupervisor.h"

#include "kextdaemon.h"

#define LEFT_BUTTON     4
#define RIGHT_BUTTON    1
#define MIDDLE_BUTTON   2
#define BUTTON4         8
#define BUTTON5         16
#define BUTTON6         32
#define NUM_BUTTONS     6

#define BUTTON_DOWN(curbuttons, button)                         (((button) & curbuttons) == (button))
#define BUTTON_UP(curbuttons, button)                           (((button) & curbuttons) == 0)
#define BUTTON_STATE_CHANGED(curbuttons, lastbuttons, button)   ((lastButtons & (button)) != (curbuttons & (button)))

typedef enum AccelerationCurve_s {
    ACCELERATION_CURVE_LINEAR   = 0,
    ACCELERATION_CURVE_WINDOWS  = 1,
    ACCELERATION_CURVE_OSX      = 2
} AccelerationCurve;

BOOL mouse_init();
BOOL mouse_cleanup();
void mouse_handle(mouse_event_t *event);
void mouse_refresh();
void mouse_update_clicktime();
