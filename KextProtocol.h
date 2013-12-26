#pragma once

#include <stdint.h>

#define MAX_LENGTH_MANUFACTURER_STRING (128)
#define MAX_LENGTH_PRODUCT_STRING (128)
#define KEYBOARD_CONFIGURATION_SIZE (256)

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
    event_type_t event_type;
    device_type_t device_type;
    uint32_t vendor_id;
    uint32_t product_id;
    uint64_t seq;
    uint64_t timestamp;
} kext_event_base_t;

typedef struct {
    kext_event_base_t base;
} device_added_event_t;

typedef struct {
    kext_event_base_t base;
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

typedef struct {
    bool is_trackpad;
} pointing_device_information_t;

typedef struct {
    bool temp;
} keyboard_device_information_t;

typedef struct {

} pointing_device_configuration_t;

typedef struct {
    char enabledKeys[KEYBOARD_CONFIGURATION_SIZE];
} keyboard_device_configuration_t;

typedef struct {
    device_type_t device_type;
    uint32_t vendor_id;
    uint32_t product_id;
    uint32_t enabled;
    union {
        pointing_device_configuration_t pointing;
        keyboard_device_configuration_t keyboard;
    };
} device_configuration_t;

typedef struct {
    device_type_t type;
    uint32_t vendor_id;
    uint32_t product_id;
    uint32_t report_interval;
    char manufacturer_string[MAX_LENGTH_MANUFACTURER_STRING];
    char product_string[MAX_LENGTH_PRODUCT_STRING];
    union {
        pointing_device_information_t pointing;
        keyboard_device_information_t keyboard;
    };
} device_information_t;

typedef enum {
    KEXT_METHOD_CONNECT,
    KEXT_METHOD_CONFIGURE_DEVICE,
    KEXT_METHOD_GET_DEVICE_INFORMATION,
    KEXT_METHOD_NUMBER_OF_METHODS
} kext_method_t;

