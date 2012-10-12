#import "UrlLabel.h"

@implementation UrlLabel

@synthesize delegate;

- (void)mouseUp:(NSEvent *)theEvent {
    
    [super mouseUp:theEvent];
    
    // call delegate
    if (delegate != nil && [delegate respondsToSelector:@selector(labelWasClicked)]) {
        [delegate performSelector:@selector(labelWasClicked) withObject:nil];
    }
}

@end
