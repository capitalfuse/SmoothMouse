#import "OverlayView.h"

#include "mouse.h"

@implementation OverlayView

- (NSRect)resizeRect
{
	const CGFloat resizeBoxSize = 16.0;
	const CGFloat contentViewPadding = 5.5;

	NSRect contentViewRect = [[self window] contentRectForFrameRect:[[self window] frame]];
	NSRect resizeRect = NSMakeRect(
                                   NSMaxX(contentViewRect) + contentViewPadding,
                                   NSMinY(contentViewRect) - resizeBoxSize - contentViewPadding,
                                   resizeBoxSize,
                                   resizeBoxSize);

	return resizeRect;
}

- (void)drawRect:(NSRect)rect
{
	[[NSColor clearColor] set];
	NSRectFill(rect);

    NSColor *color = [NSColor colorWithSRGBRed:1.0 green:0.0 blue:0.5 alpha:0.5];
    [color set];

    CGPoint mousePos = mouse_get_current_pos();

    NSRect windowRect = [[NSScreen mainScreen] frame];

    NSRect rect2;

    rect2.origin.x = mousePos.x - 15;
    rect2.origin.y = windowRect.size.height - mousePos.y - 15;
    rect2.size.width = 30;
    rect2.size.height = 30;

    NSRectFill(rect2);
}

@end
