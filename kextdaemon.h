#pragma once

#include <stdint.h>

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
