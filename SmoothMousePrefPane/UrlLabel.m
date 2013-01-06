#import "UrlLabel.h"

@implementation UrlLabel

- (void)mouseUp:(NSEvent *)theEvent {
    
    [super mouseUp:theEvent];

    if (_delegate != nil && [_delegate respondsToSelector:@selector(urlWasClicked)]) {
        [_delegate performSelector:@selector(urlWasClicked) withObject:nil];
    }
}

@end
