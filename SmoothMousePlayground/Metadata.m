

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

-(BOOL) getMetadataForVendorID:(uint32_t)vid andProductID:(uint32_t)pid manufacturer:(NSString **)manufacturer product:(NSString **)product icon:(NSImage **)icon;
{
    NSString *dataDirectory = [[NSFileManager defaultManager] getDataDirectory];
    LOG(@"data directory: %@", dataDirectory);
    NSString *dataFilename = [NSString stringWithFormat:@"%@/%d_%d.xml", dataDirectory, vid, pid];
    LOG(@"data filename: %@", dataFilename);

    NSString *iconDirectory = [[NSFileManager defaultManager] getIconDirectory];
    LOG(@"icon directory: %@", iconDirectory);
    NSString *iconFilename = [NSString stringWithFormat:@"%@/%d_%d.png", iconDirectory, vid, pid];
    LOG(@"icon filename: %@", iconFilename);

    BOOL dataExists = [[NSFileManager defaultManager] fileExistsAtPath:dataFilename];
    BOOL iconExists = [[NSFileManager defaultManager] fileExistsAtPath:iconFilename];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://metadata.smoothmouse.com/devices/%d/%d/", vid, pid]];
    LOG(@"metadata url: %@", url);

    if (dataExists) {
        LOG(@"exists, load xml and/or icon");
        NSString *manufacturerFromXml;
        NSString *productFromXml;
        BOOL ok = [self parseXml:dataFilename manufacturer:&manufacturerFromXml product:&productFromXml iconUrl:nil];
        if (!ok) {
            LOG("failed to parse xml, refreshing in background");
            [self saveMetadataAndIconFromUrl:url forVendorID:vid andProductID:pid dataFilename:dataFilename iconFilename:iconFilename];
            return NO;
        }
        NSImage *loadedIcon = nil;
        if (iconExists) {
            loadedIcon = [[NSImage alloc] initWithContentsOfFile: iconFilename];
            if (loadedIcon == nil) {
                LOG("failed to parse xml, refreshing in background");
                [self saveMetadataAndIconFromUrl:url forVendorID:vid andProductID:pid dataFilename:dataFilename iconFilename:iconFilename];
                return NO;
            }
        }
        *manufacturer = manufacturerFromXml;
        *product = productFromXml;
        if (iconExists) {
            *icon = loadedIcon;
        }
        return YES;
    } else {
        [self saveMetadataAndIconFromUrl:url forVendorID:vid andProductID:pid dataFilename:dataFilename iconFilename:iconFilename];
        return NO;
    }
}

-(void) saveMetadataAndIconFromUrl:(NSURL *)url
                       forVendorID:(uint32_t)vid
                      andProductID:(uint32_t)pid
                      dataFilename:(NSString *)dataFilename
                      iconFilename:(NSString *)iconFilename
{
    dispatch_queue_t myprocess_queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
    dispatch_async(myprocess_queue, ^{
        BOOL ok;

        ok = [self saveMetadata:url filename:dataFilename];
        if (!ok) {
            LOG(@"failed to retrieve metadata from url: %@", url);
            return;
        }

        NSString *manufacturer = nil;
        NSString *product = nil;
        NSURL *iconUrl = nil;

        ok = [self parseXml:dataFilename manufacturer:&manufacturer product:&product iconUrl:&iconUrl];
        if (!ok) {
            LOG(@"failed to parse xml");
            return;
        }

        LOG(@"metadata from url %@: manufacturer: %@, product: %@, iconUrl: %@", url, manufacturer, product, iconUrl);

        if (iconUrl != nil) {
            ok = [self saveIcon: iconUrl filename:iconFilename];
            if (!ok) {
                LOG(@"failed to retrieve icon from url: %@", iconUrl);
                return;
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate didReceiveMetadataForVendorID:vid andProductID:pid];
        });

        return;
    });
    return;
}

-(BOOL)saveMetadata:(NSURL *)url
           filename:(NSString *)filename
{
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

    // TEMP: how to convert nsdata to nsstring, either null-terminated or not
    //NSString* xml = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    // or
    // NSString* xml = [NSString stringWithUTF8String:[data bytes]];

    [data writeToFile:filename atomically:YES];

    return YES;
}

-(BOOL)saveIcon:(NSURL *)url
       filename:(NSString *)filename
{
    // TODO: duplicate code for downloading, reuse saveMetadata code
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

    if (icon && iconUrl) {
        *iconUrl = [NSURL URLWithString:icon];
    }

    return YES;
}

@end
