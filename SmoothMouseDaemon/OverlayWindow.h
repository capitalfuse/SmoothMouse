#import <Cocoa/Cocoa.h>

@interface OverlayWindow : NSWindow {
    NSView *childContentView;
}

-(void) redrawView;

@end
