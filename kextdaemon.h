#pragma once

#include <stdint.h>

#define KEXT_CONF_MOUSE_ENABLED     (1 << 0)
#define KEXT_CONF_TRACKPAD_ENABLED  (1 << 1)
#define KEXT_CONF_QUARTZ_OLD        (1 << 2)

typedef enum {
	kDeviceTypeMouse,
	kDeviceTypeTrackpad,
    kDeviceTypeUnknown
} device_type_t;

typedef struct mouse_event_s {
    device_type_t device_type;
	int buttons;
	int dx;
	int dy;
    uint64_t timestamp;
    uint64_t seqnum;
} mouse_event_t;

enum {
    kConfigureMethod,
    kNumberOfMethods
};
