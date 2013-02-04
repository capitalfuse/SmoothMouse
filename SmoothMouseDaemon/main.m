#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

int main(int argc, char *argv[])
{
    @autoreleasepool {
        AppDelegate *delegate = [[AppDelegate alloc] initWithArgc: argc andArgv:argv];
        NSApplication *application = [NSApplication sharedApplication];
        [application setDelegate:delegate];
        [NSApp run];
    }
}

