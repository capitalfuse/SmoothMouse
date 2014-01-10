
#import <Foundation/Foundation.h>

@interface MetadataParser : NSObject<NSXMLParserDelegate> {
    NSString *currentElement;
    NSString *manufacturer;
    NSString *product;
    NSString *icon;
}

-(BOOL) parse:(NSString *)filename;

@property (copy) NSString *manufacturer;
@property (copy) NSString *product;
@property (copy) NSString *icon;

@end
