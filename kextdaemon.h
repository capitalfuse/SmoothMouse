typedef enum {
	eMouseEvent,
	eUnknownType
} event_type_t;

typedef struct mouse_event_s {
	int buttons;
	int dx;
	int dy;
} mouse_event_t;