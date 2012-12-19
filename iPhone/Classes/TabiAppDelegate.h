//
//  TabiAppDelegate.h
//  Tabi
//
//  Created by Vyacheslav Zakovyrya on 1/12/10.
//  Copyright __MyCompanyName__ 2010. All rights reserved.
//

#import "RootViewController.h"
#import "EventNotifyingUIWindow.h"
#import "ScreenSaverController.h"
#import "RootViewController.h"

@interface TabiAppDelegate : NSObject <UIWindowEventDelegate, UIApplicationDelegate> {
    EventNotifyingUIWindow *window;
    UINavigationController *navigationController;
    NSTimer *screenSaverTimer;
    ScreenSaverController *screenSaverController;
    RootViewController *rootViewController;
}

@property (nonatomic, retain) IBOutlet UIWindow *window;
@property (nonatomic, retain) IBOutlet UINavigationController *navigationController;
@property (nonatomic, assign) IBOutlet RootViewController *rootViewController;
@property (nonatomic, retain) NSTimer *screenSaverTimer;

@end

