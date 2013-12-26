//
//  AppDelegate.h
//  InputMeasurement
//
//  Created by Daniel Åkerud on 6/23/13.
//  Copyright (c) 2013 -. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate> {
    id eventMonitor;
    double timeMouseMs;
    double timeKeyMs;
    double averageMs;
    __weak NSTextField *_label;
}

@property (assign) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSTextField *label;

@end
