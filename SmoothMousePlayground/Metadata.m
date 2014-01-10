

#import "Metadata.h"
#import "Debug.h"
#import "MetadataParser.h"

#define MAX_HTTP_REQUEST_TIMEOUT_SECONDS (5)

@interface NSFileManager (NSFileManagerAdditions)

- (NSString *)findOrCreateDirectory:(NSSearchPathDirectory)searchPathDirectory
                           inDomain:(NSSearchPathDomainMask)domainMask
                appendPathComponent:(NSString *)appendComponent;
- (NSString *)getDataDirectory;
- (NSString *)getIconDirectory;

@end

@implementation NSFileManager (NSFileManagerAdditions)

- (NSString *)findOrCreateDirectory:(NSSearchPathDirectory)searchPathDirectory
                           inDomain:(NSSearchPathDomainMask)domainMask
                appendPathComponent:(NSString *)appendComponent
{
    NSArray* paths = NSSearchPathForDirectoriesInDomains(searchPathDirectory, domainMask, YES);
    if ([paths count] == 0) {
        LOG(@"Call to NSSearchPathForDirectoriesInDomains failed");
        return nil;
    }

    NSString *resolvedPath = [paths objectAtIndex:0];
    if (appendComponent) {
        resolvedPath = [resolvedPath stringByAppendingPathComponent:appendComponent];
    }

    NSError *error;
    BOOL success = [self createDirectoryAtPath:resolvedPath withIntermediateDirectories:YES attributes:nil error:&error];
    if (!success) {
        LOG(@"Failed to create directory: %@", resolvedPath);
        return nil;
    }

    return resolvedPath;
}

- (NSString *)getDataDirectory
{
    NSString *subdirectory = @"SmoothMouse/data";

    NSString *result = [self
                        findOrCreateDirectory:NSApplicationSupportDirectory
                        inDomain:NSUserDomainMask
                        appendPathComponent:subdirectory];
    if(!result)
    {
        LOG(@"Failed to find icon directory");
    }

    return result;
}

- (NSString *)getIconDirectory
{
    NSString *subdirectory = @"SmoothMouse/icons";

    NSString *result = [self
                        findOrCreateDirectory:NSApplicationSupportDirectory
                        inDomain:NSUserDomainMask
                        appendPathComponent:subdirectory];
    if(!result)
    {
        LOG(@"Failed to find icon directory");
    }

    return result;
}

@end

@implementation Metadata

-(void) setDelegate:(id)delegate_
{
    delegate = delegate_;
}

-(BOOL) getMetadataForVendorID:(uint32_t)vid andProductID:(uint32_t)pid manufacturer:(NSString **) manufacturer product:(NSString **)product icon:(NSImage **)icon completion:(void(^)(void))callback;
{
    NSString *dataDirectory = [[NSFileManager defaultManager] getDataDirectory];
    LOG(@"data directory: %@", dataDirectory);
    NSString *dataFilename = [NSString stringWithFormat:@"%@/%d_%d.xml", dataDirectory, vid, pid];
    LOG(@"data filename: %@", dataFilename);

    NSString *iconDirectory = [[NSFileManager defaultManager] getIconDirectory];
    LOG(@"icon directory: %@", iconDirectory);
    NSString *iconFilename = [NSString stringWithFormat:@"%@/%d_%d.xml", iconDirectory, vid, pid];
    LOG(@"icon filename: %@", iconFilename);

    BOOL dataExists = [[NSFileManager defaultManager] fileExistsAtPath:dataFilename];
    BOOL iconExists = [[NSFileManager defaultManager] fileExistsAtPath:iconFilename];

    if (dataExists && iconExists) {
        LOG(@"exists, load xml and icon");
        return YES;
    } else {
        LOG(@"retrieving metadata and icon from server");
        dispatch_queue_t myprocess_queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
        dispatch_async(myprocess_queue, ^{
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://metadata.smoothmouse.com/devices/%d/%d/", vid, pid]];
            LOG(@"metadata url: %@", url);
            BOOL ok = [self downloadMetadataAndIconFromUrl:url forVendorID:vid andProductID:pid dataFilename:dataFilename iconFilename:iconFilename];
            if (!ok) {
                LOG(@"call to downloadMetadataAndIconFromUrl failed");
            }
        });
        return NO;
    }
}

-(BOOL) downloadMetadataAndIconFromUrl:(NSURL *)url
                           forVendorID:(uint32_t)vid
                          andProductID:(uint32_t)pid
                          dataFilename:(NSString *)dataFilename
                          iconFilename:(NSString *)iconFilename
{
    NSString *manufacturer = nil;
    NSString *product = nil;
    NSURL *iconUrl = nil;
    NSImage *icon = nil;

    BOOL ok = [self getMetadataFromUrl:url filename:dataFilename manufacturer:&manufacturer product:&product iconUrl:&iconUrl];
    if (!ok) {
        LOG(@"failed to retrieve metadata from url: %@", url);
        return NO;
    }

    LOG(@"metadata from url %@: manufacturer: %@, product: %@, iconUrl: %@", url, manufacturer, product, iconUrl);

    ok = [self getIconFromUrl: iconUrl filename:iconFilename icon:&icon];
    if (!ok) {
        LOG(@"failed to retrieve icon from url: %@", iconUrl);
        return NO;
    }

    [delegate didReceiveMetadataForVendorID:vid andProductID:pid manufacturer:manufacturer product:product icon:icon];

    return YES;
}

-(BOOL)getMetadataFromUrl:(NSURL *)url
                 filename:(NSString *)filename
             manufacturer:(NSString **)manufacturer
                  product:(NSString **)product
                  iconUrl:(NSURL **)iconUrl
{
    // use NSURLConnection to download the metadata to Application Support/SmoothMouse/Metadata/x_y.metadata

    NSURLRequest *request;
    NSHTTPURLResponse *response;
    NSError *error;
    NSData *data;
    LOG(@"url: %@", url);

    request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:MAX_HTTP_REQUEST_TIMEOUT_SECONDS];

    data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];

    long statusCode = [response statusCode];

    LOG(@"response status code: %ld", statusCode);

    if (statusCode != 200) {
        LOG(@"response not 200 OK");
        return NO;
    }

    [data writeToFile:filename atomically:YES];

    //NSString* xml = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    // or
    // NSString* xml = [NSString stringWithUTF8String:[data bytes]];
    BOOL ok = [self parseXml:filename manufacturer:manufacturer product:product iconUrl:iconUrl];
    if (!ok) {
        LOG(@"Failed to parse xml");
        return NO;
    }

    return YES;
}

-(BOOL)getIconFromUrl:(NSURL *)url
             filename:(NSString *)filename
                 icon:(NSImage **)icon
{
    // use NSURLDownload to download the icon to Application Support/SmoothMouse/Icons/x_y.png

    LOG(@"url: %@", url);

    return YES;
}

-(BOOL)parseXml:(NSString *)filename manufacturer:(NSString **)manufacturer product:(NSString **)product iconUrl:(NSURL **)iconUrl
{
    MetadataParser *parser = [[[MetadataParser alloc] init] autorelease];
    BOOL ok = [parser parse:filename];
    if (!ok) {
        LOG(@"failed to parse xml document");
        return NO;
    }

    NSString *icon;

    *manufacturer = parser.manufacturer;
    *product = parser.product;
    icon = parser.icon;

    if (icon) {
        *iconUrl = [NSURL URLWithString:icon];
    }

    return YES;
}

@end
