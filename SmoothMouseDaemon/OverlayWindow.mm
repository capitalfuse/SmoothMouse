#import "OverlayWindow.h"
#import "OverlayView.h"
#import "Debug.h"

@implementation OverlayWindow

-(id) init {
    int windowLevel = CGShieldingWindowLevel();
    NSRect windowRect = [[NSScreen mainScreen] frame];

    self = [super initWithContentRect:windowRect
                            styleMask:NSBorderlessWindowMask
                              backing:NSBackingStoreBuffered
                                defer:NO
                               screen:[NSScreen mainScreen]];

    if (self) {
        [self setReleasedWhenClosed:YES];
        [self setLevel:windowLevel];
        [self setBackgroundColor:[NSColor colorWithCalibratedRed:0.0
                                                           green:1.0
                                                            blue:0.0
                                                           alpha:0.5]];
        [self setAlphaValue:1.0];
        [self setOpaque:NO];
        [self setIgnoresMouseEvents:YES];
        [self makeKeyAndOrderFront:nil];
    }

    return self;
}

-(void) redrawView {
    [childContentView setNeedsDisplay:YES];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter]
     removeObserver:self];
    [super dealloc];
}

- (void)setContentSize:(NSSize)newSize
{
	NSSize sizeDelta = newSize;
	NSSize childBoundsSize = [childContentView bounds].size;
	sizeDelta.width -= childBoundsSize.width;
	sizeDelta.height -= childBoundsSize.height;

	OverlayView *frameView = [super contentView];
	NSSize newFrameSize = [frameView bounds].size;
	newFrameSize.width += sizeDelta.width;
	newFrameSize.height += sizeDelta.height;

	[super setContentSize:newFrameSize];
}

- (void)setContentView:(NSView *)aView
{
	if ([childContentView isEqualTo:aView])
	{
		return;
	}

	NSRect bounds = [self frame];
	bounds.origin = NSZeroPoint;

	OverlayView *frameView = [super contentView];
	if (!frameView)
	{
		frameView = [[[OverlayView alloc] initWithFrame:bounds] autorelease];

		[super setContentView:frameView];
	}

	if (childContentView)
	{
		[childContentView removeFromSuperview];
	}
	childContentView = aView;
	[childContentView setFrame:[self contentRectForFrameRect:bounds]];
	[childContentView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[frameView addSubview:childContentView];
}

- (NSView *)contentView
{
	return childContentView;
}

- (BOOL)canBecomeKeyWindow
{
	return YES;
}

- (BOOL)canBecomeMainWindow
{
	return YES;
}

- (NSRect)contentRectForFrameRect:(NSRect)windowFrame
{
	windowFrame.origin = NSZeroPoint;
	return NSInsetRect(windowFrame, 0, 0);
}

+ (NSRect)frameRectForContentRect:(NSRect)windowContentRect styleMask:(NSUInteger)windowStyle
{
	return NSInsetRect(windowContentRect, -0, -0);
}

@end
