#import "VersionLabel.h"

@implementation VersionLabel

- (void)mouseDown:(NSEvent *)theEvent {

    [super mouseUp:theEvent];

    if (_delegate != nil && [_delegate respondsToSelector:@selector(versionWasClicked)]) {
        [_delegate performSelector:@selector(versionWasClicked) withObject:nil];
    }
}

@end
