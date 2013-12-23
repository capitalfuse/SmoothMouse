#pragma once

#include <stdint.h>

#define MAX_LENGTH_MANUFACTURER_STRING (32)
#define MAX_LENGTH_PRODUCT_STRING (32)

typedef enum {
    EVENT_TYPE_DEVICE_ADDED,
    EVENT_TYPE_DEVICE_REMOVED,
    EVENT_TYPE_POINTING,
    EVENT_TYPE_KEYBOARD
} event_type_t;

typedef enum {
	DEVICE_TYPE_POINTING,
    DEVICE_TYPE_KEYBOARD,
    DEVICE_TYPE_UNKNOWN
} device_type_t;

typedef struct {
    event_type_t type;
    uint32_t vendor_id;
    uint32_t product_id;
    uint64_t seq;
    uint64_t timestamp;
} kext_event_base_t;

typedef struct {
    kext_event_base_t base;
    char manufacturer_string[MAX_LENGTH_MANUFACTURER_STRING];
    char product_string[MAX_LENGTH_PRODUCT_STRING];
} device_added_event_t;

typedef struct {
    kext_event_base_t base;
    char manufacturer_string[MAX_LENGTH_MANUFACTURER_STRING];
    char product_string[MAX_LENGTH_PRODUCT_STRING];
} device_removed_event_t;

typedef struct {
    kext_event_base_t base;
	uint32_t buttons;
	int32_t dx;
	int32_t dy;
    uint32_t is_trackpad;
} pointing_event_t;

typedef struct keyboard_event_s {
    kext_event_base_t base;
    unsigned int key;
} keyboard_event_t;

typedef union {
    kext_event_base_t base;
    device_added_event_t device_added;
    device_removed_event_t device_removed;
    pointing_event_t pointing;
    keyboard_event_t keyboard;
} kext_event_t;

typedef enum {
    KEXT_METHOD_CONFIGURE_DEVICE,
    KEXT_METHOD_NUMBER_OF_METHODS
} kext_method_t;

