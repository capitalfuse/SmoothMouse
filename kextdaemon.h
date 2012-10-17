#pragma once

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
    unsigned long long timestamp;
} mouse_event_t;

enum {
    kConfigureMethod,
    kNumberOfMethods
};
