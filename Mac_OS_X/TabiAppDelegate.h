//
//  TabiAppDelegate.h
//  Tabi
//
//  Created by Vyacheslav Zakovyrya on 1/24/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Growl/GrowlApplicationBridge.h>
#import "TabiAgent.h"

@interface TabiAppDelegate : NSObject <NSApplicationDelegate, GrowlApplicationBridgeDelegate, TabiAgentDelegate> {
    NSImage *noServersFoundIcon;
    NSImage *serversFoundIcon;
    NSImage *connectedToServerIcon;
    
    IBOutlet NSStatusItem *statusItem;
    IBOutlet NSMenu *statusItemMenu;
    IBOutlet NSMenuItem *agentStatusMenuItem;
    
    TabiAgent *tabiAgent;
    
    NSMutableArray *servers;
    NSDictionary *serverConnectedTo;
}

@property (nonatomic, retain) NSDictionary *serverConnectedTo;

@end
