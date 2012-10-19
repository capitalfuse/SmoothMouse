#import "UrlLabel.h"

@implementation UrlLabel

- (void)mouseUp:(NSEvent *)theEvent {
    
    [super mouseUp:theEvent];

    if (_delegate != nil && [_delegate respondsToSelector:@selector(labelWasClicked)]) {
        [_delegate performSelector:@selector(labelWasClicked) withObject:nil];
    }
}

@end
