
#import <Cocoa/Cocoa.h>

@interface DeviceCellView : NSTableCellView {
@private
    IBOutlet NSTextField *productTextField;
    IBOutlet NSTextField *manufacturerTextField;
    IBOutlet NSImageView *deviceImage;
}

@property(assign) NSTextField *productTextField;
@property(assign) NSTextField *manufacturerTextField;
@property(assign) NSImageView *deviceImage;

@end
