//
//  TabiAppDelegate.m
//  Tabi
//
//  Created by Vyacheslav Zakovyrya on 1/12/10.
//  Copyright __MyCompanyName__ 2010. All rights reserved.
//

#import "TabiAppDelegate.h"
#import "RootViewController.h"
#import "SOCKSServer.h"

@implementation TabiAppDelegate

@synthesize window;
@synthesize navigationController, rootViewController;
@synthesize screenSaverTimer;


#pragma mark -
#pragma mark Application lifecycle

#define SCREEN_SAVER_TIMEOUT 100000000000000

- (void)turnScreenSaverOff {
    if (screenSaverController.view == [window.subviews lastObject]) {
        [screenSaverController.view removeFromSuperview];
    }
}

- (void)eventHappened:(UIEvent *)event {
    [self.screenSaverTimer invalidate];
    self.screenSaverTimer = [NSTimer scheduledTimerWithTimeInterval:SCREEN_SAVER_TIMEOUT target:self selector:@selector(screenSaverTimerFired:) userInfo:nil repeats:NO];
    
    [self turnScreenSaverOff];
}

- (void)screenSaverTimerFired:(NSTimer *)timer {
    [window addSubview:screenSaverController.view];
}

- (void)proximityChanged:(NSNotification *)notification {
    [self turnScreenSaverOff];
    if (![UIDevice currentDevice].proximityState) {
        [self.screenSaverTimer invalidate];
        self.screenSaverTimer = [NSTimer scheduledTimerWithTimeInterval:SCREEN_SAVER_TIMEOUT target:self selector:@selector(screenSaverTimerFired:) userInfo:nil repeats:NO];
    }
}

- (void)applicationDidFinishLaunching:(UIApplication *)application {
  	[[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    [UIDevice currentDevice].proximityMonitoringEnabled = YES;
    
    if (![UIDevice currentDevice].proximityMonitoringEnabled) {
        NSLog(@"could not enable proximity monitoring");
    }
    else {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(proximityChanged:) name:UIDeviceProximityStateDidChangeNotification object:nil];
    }
    
    screenSaverController = [[ScreenSaverController alloc] initWithNibName:@"ScreenSaverController" bundle:nil];
    
	[window addSubview:[navigationController view]];
    window.eventDelegate = self;
    [window makeKeyAndVisible];
    
    self.screenSaverTimer = [NSTimer scheduledTimerWithTimeInterval:SCREEN_SAVER_TIMEOUT target:self selector:@selector(screenSaverTimerFired:) userInfo:nil repeats:NO];
}

- (void)applicationWillResignActive:(UIApplication *)application {
    BOOL SOCKSServerIsRunning = [rootViewController isSOCKSServerRunning];
    [[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithBool:SOCKSServerIsRunning] forKey:@"SOCKSServerWasRunning"];
    if (SOCKSServerIsRunning) {
        [rootViewController stopSOCKSServer];
    }
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    if ([[NSUserDefaults standardUserDefaults] valueForKey:@"SOCKSServerWasRunning"]) {
        [rootViewController startSOCKSServer];
    }
}


- (void)applicationWillTerminate:(UIApplication *)application {
	// Save data if appropriate
}


#pragma mark -
#pragma mark Memory management

- (void)dealloc {
    self.screenSaverTimer = nil;
    
	[navigationController release];
	[window release];
    
	[super dealloc];
}


@end

