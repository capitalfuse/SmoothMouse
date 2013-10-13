
#import "AppDelegate.h"

#import <FeedbackReporter/FRFeedbackReporter.h>

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [[FRFeedbackReporter sharedReporter] reportFeedback];
}

@end
