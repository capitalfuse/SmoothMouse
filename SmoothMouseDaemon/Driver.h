
#pragma once

extern int numCoalescedEvents;

typedef enum Driver_s {
    DRIVER_QUARTZ_OLD,
    DRIVER_QUARTZ,
    DRIVER_IOHID
} Driver;

typedef enum driver_event_id_s {
    DRIVER_EVENT_ID_MOVE,
    DRIVER_EVENT_ID_BUTTON,
    DRIVER_EVENT_ID_TERMINATE
} driver_event_id_t;

typedef struct {
    CGEventType type;
    CGPoint pos;
    int buttons;
    int otherButton;
    int nclicks;
} driver_button_event_t;

typedef struct {
    CGEventType type;
    CGPoint pos;
    int buttons;
    int otherButton;
    int deltaX;
    int deltaY;
} driver_move_event_t;

typedef struct {
    driver_event_id_t id;
    uint64_t seqnum;
    union {
        driver_move_event_t move;
        driver_button_event_t button;
    };
} driver_event_t;

BOOL driver_init();
BOOL driver_cleanup();
BOOL driver_post_event(driver_event_t *event);
const char *driver_quartz_event_type_to_string(CGEventType type);
const char *driver_iohid_event_type_to_string(int type);
const char *driver_get_driver_string(int driver);



