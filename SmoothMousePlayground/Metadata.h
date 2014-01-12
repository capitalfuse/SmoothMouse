
#import <Foundation/Foundation.h>

@protocol Metadata<NSObject>
- (void)didReceiveMetadataForVendorID:(uint32_t)vid andProductID:(uint32_t)pid;
@end

@interface Metadata : NSObject <NSXMLParserDelegate> {
    id<Metadata> delegate;
}

-(void) setDelegate: (id) delegate;
-(BOOL) getMetadataForVendorID:(uint32_t)vid andProductID:(uint32_t)pid manufacturer:(NSString **) manufacturer product:(NSString **)product icon:(NSImage **)icon;

@end
