
#import "MetadataParser.h"
#import "Debug.h"

#define ELEMENT_VENDOR_NAME @"VendorName"
#define ELEMENT_PRODUCT_NAME @"ProductName"
#define ELEMENT_ICON @"Icon"

@implementation MetadataParser

@synthesize manufacturer;
@synthesize product;
@synthesize icon;

-(BOOL) parse:(NSString *)filename
{
    NSURL *xmlUrl = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@", filename]];
    if (!xmlUrl) {
        LOG(@"illegal filename to xml document: %@", filename);
        return NO;
    }

    LOG(@"Parsing xml from url: %@", xmlUrl);
    
    NSXMLParser *parser = [[NSXMLParser alloc] initWithContentsOfURL:xmlUrl];

    [parser setDelegate:self];
    [parser parse];
    [parser release];

    if (manufacturer == nil && product == nil && icon == nil) {
        LOG(@"no data in xml");
        return NO;
    }

    return YES;
}

- (void)parserDidStartDocument:(NSXMLParser *)parser {
    LOG(@"enter");
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qualifiedName attributes:(NSDictionary *)attributeDict {
    currentElement = elementName;
    LOG(@"enter, element: %@", elementName);
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    LOG(@"enter, currentElement: %@, chars: %@", currentElement, string);
    if ([ELEMENT_VENDOR_NAME isEqualToString:currentElement]) {
        manufacturer = [string copy];
    }
    if ([ELEMENT_PRODUCT_NAME isEqualToString:currentElement]) {
        product = [string copy];
    }
    if ([ELEMENT_ICON isEqualToString:currentElement]) {
        icon = [string copy];
    }
}

- (void)parserDidEndDocument:(NSXMLParser *)parser {
    LOG(@"enter");
}

@end
