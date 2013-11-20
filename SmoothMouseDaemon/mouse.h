
#pragma once

#import "MouseSupervisor.h"

#include "KextProtocol.h"

#define LEFT_BUTTON     (1 << 0)
#define RIGHT_BUTTON    (1 << 1)
#define MIDDLE_BUTTON   (1 << 2)
#define BUTTON4         (1 << 3)
#define BUTTON5         (1 << 4)
#define BUTTON6         (1 << 5)
#define NUM_BUTTONS     6

#define BUTTON_DOWN(curbuttons, button)                         (((button) & curbuttons) == (button))
#define BUTTON_UP(curbuttons, button)                           (((button) & curbuttons) == 0)
#define BUTTON_STATE_CHANGED(curbuttons, lastbuttons, button)   ((lastButtons & (button)) != (curbuttons & (button)))

extern int totalNumberOfLostEvents;

typedef enum RefreshReason_s {
    REFRESH_REASON_UNKNOWN,
    REFRESH_REASON_SEQUENCE_NUMBER_INVALID,
    REFRESH_REASON_POSITION_TAMPERING,
    REFRESH_REASON_BUTTON_CLICK,
    REFRESH_REASON_FORCE_DRAG_REFRESH
} RefreshReason;

typedef enum AccelerationCurve_s {
    ACCELERATION_CURVE_LINEAR   = 0,
    ACCELERATION_CURVE_WINDOWS  = 1,
    ACCELERATION_CURVE_OSX      = 2
} AccelerationCurve;

BOOL mouse_init();
BOOL mouse_cleanup();
void mouse_process_kext_event(mouse_event_t *event);
void mouse_refresh(RefreshReason reason);
void mouse_update_clicktime();
CGPoint mouse_get_current_pos();
