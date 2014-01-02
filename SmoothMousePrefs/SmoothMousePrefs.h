
#import <PreferencePanes/PreferencePanes.h>

#import "Kext.h"

@interface SmoothMousePrefs : NSPreferencePane<NSTableViewDelegate, NSTableViewDataSource> {
    @private
    Kext *kext;
}

- (void)mainViewDidLoad;

@end
