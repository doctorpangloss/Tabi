//
//  TabiAppDelegate.m
//  Tabi
//
//  Created by Vyacheslav Zakovyrya on 1/24/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "TabiAppDelegate.h"
#import "NSAppUtils.h"
#import "NSDictionaryAdditions.h"
#import "CollectionsAdditions.h"
#import "BlocksAdditions.h"

@interface NSString(TabiAdditions)

@end

@implementation NSString(TabiAdditions)

- (NSString *)hostNameWithoutLocalSuffix {
    NSString *suffix = @".local.";
    if ([self length] > [suffix length] && 
        [suffix isEqualToString:[self substringWithRange:NSMakeRange([self length] - [suffix length], [suffix length])]]) {
        return [self substringToIndex:[self length] - [suffix length]];
    }
    
    return self;
}

- (void)copyToPasteboard {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setData:[self dataUsingEncoding:NSUTF8StringEncoding] forType:@"public.utf8-plain-text"];
}

@end


@implementation TabiAppDelegate

@synthesize serverConnectedTo;

- (void)updateIcon {
    NSImage *icon = [servers count] ? nil != serverConnectedTo ? connectedToServerIcon : serversFoundIcon : noServersFoundIcon;
    [statusItem setImage:icon];
    [statusItem setAlternateImage:icon];
    [statusItem setHighlightMode:YES];
}

- (void)updateTitle {
    NSString *title = ![servers count] ? @"Waiting for Tabi Server..." : [servers count] == 1 ? @"Found Tabi Server..." : [NSString stringWithFormat:@"Found %d Tabi Servers...", [servers count]];

    [agentStatusMenuItem setTitle:title];    
}

- (void)clearStatusItemMenu {
    [[statusItemMenu itemArray] forEachDo:^(id item, NSUInteger idx) {
        id representedObject = [item representedObject];
        if (nil != representedObject) {
            [statusItemMenu removeItem:item];
        }
    }];
    if ([[statusItemMenu itemAtIndex:3] isSeparatorItem]) {
        [statusItemMenu removeItemAtIndex:3];
    }
}

- (void)updateView {
    NSLog(@"updating view... Tabi servers: %@, currently connected to %@", servers, serverConnectedTo);
    
    [self updateIcon];
    [self updateTitle];
    [self clearStatusItemMenu];
    
    if (![servers count]) {
        return;
    }
    
    [statusItemMenu insertItem:[NSMenuItem separatorItem] atIndex:2];
    __block NSUInteger currentIndex = 3;
    [servers forEachDo:^(id serverInfo, NSUInteger idx) {
        if (![serverInfo canConnect]) {
            return;
        }

        NSString *serverAddress = [serverInfo valueForKey:@"serverAddressToConnectTo"];
        NSString *hostName = [serverInfo hostNameWithoutLocalSuffix];
        NSNumber *serverPort = [serverInfo valueForKey:@"serverPort"];
                
        NSMenuItem *serverMenuItem = [statusItemMenu insertItemWithTitle:hostName action:@selector(toggleConnectionToServerFromMenuItem:)
                                                            keyEquivalent:@"" atIndex:currentIndex++];
        [serverMenuItem setRepresentedObject:serverInfo];
        [serverMenuItem setTarget:self];
        [serverMenuItem setState:([serverInfo isEqualToDictionary:serverConnectedTo] ? NSOnState : NSOffState)];

        NSString *addressMenuTitle = [NSString stringWithFormat:@"%@:%d", serverAddress, [serverPort intValue]];
        NSMenuItem *addressMenuItem = [statusItemMenu insertItemWithTitle:addressMenuTitle action:nil keyEquivalent:@"" atIndex:currentIndex++];
        [addressMenuItem setIndentationLevel:1];
        [addressMenuItem setRepresentedObject:serverAddress];
        
        NSMenu *addressMenu = [[[NSMenu alloc] init] autorelease];
        [statusItemMenu setSubmenu:addressMenu forItem:addressMenuItem];
        
        NSMenuItem *copyAddressToPasteboardItem = [addressMenu insertItemWithTitle:@"Copy Address" action:nil keyEquivalent:@"" atIndex:0];
        [copyAddressToPasteboardItem setTarget:serverAddress];
        [copyAddressToPasteboardItem setAction:@selector(copyToPasteboard)];
        [copyAddressToPasteboardItem setRepresentedObject:serverAddress];
        
        NSString *portStr = [NSString stringWithFormat:@"%d", [serverPort intValue]];
        NSMenuItem *copyPortToPasteboardItem = [addressMenu insertItemWithTitle:@"Copy Port" action:nil keyEquivalent:@"" atIndex:1];
        [copyPortToPasteboardItem setRepresentedObject:portStr];
        [copyPortToPasteboardItem setTarget:portStr];
        [copyPortToPasteboardItem setAction:@selector(copyToPasteboard)];
    }];
    
    [statusItemMenu update];
}

- (void)growlNotifyWithTitle:(NSString *)title description:(NSString *)description notificationName:(NSString *)notificationName {
    if (![GrowlApplicationBridge isGrowlInstalled] || ![GrowlApplicationBridge isGrowlRunning]) {
        return;
    }
    NSLog(@"sending Growl notification. Title: %@; Description: %@", title, description);
    [GrowlApplicationBridge notifyWithTitle:title description:description notificationName:notificationName iconData:nil priority:0 isSticky:NO clickContext:nil];
}

- (void)setupStatusItem {
    NSSize iconSize = NSMakeSize(16, 16);
    noServersFoundIcon = [[NSImage imageNamed:@"snail_16_black_white"] retain];
    serversFoundIcon = [[NSImage imageNamed:@"snail_16_black_white"] retain];
    connectedToServerIcon = [[NSImage imageNamed:@"snail_16_yellow"] retain];
    [serversFoundIcon setSize:iconSize];
    [noServersFoundIcon setSize:iconSize];
    [connectedToServerIcon setSize:iconSize];
    
    statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength] retain];
    [statusItem setImage:noServersFoundIcon];
    [statusItem setMenu:statusItemMenu];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    servers = [[NSMutableArray alloc] init];
    
    tabiAgent = [[TabiAgent alloc] init];
    tabiAgent.delegate = self;
    [tabiAgent start];
    
    [GrowlApplicationBridge setGrowlDelegate:self];
    [self setupStatusItem];
    [self updateView];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    if (nil != serverConnectedTo) {
        [tabiAgent requestDisconnectionFromServer:serverConnectedTo shouldWait:YES];
    }
}

- (IBAction)toggleConnectionToServerFromMenuItem:(id)sender {
    NSDictionary *serverInfo = [sender representedObject];
    [serverConnectedTo isEqualToDictionary:serverInfo] ? [tabiAgent requestDisconnectionFromServer:serverInfo shouldWait:NO] : [tabiAgent requestConnectionToServer:serverInfo];
}

- (NSDictionary *)registrationDictionaryForGrowl {
    NSArray *notifications = $arr(@"Server is gone", @"Server found", @"Connected to server", @"Disconnected from server");
    return $dict(GROWL_NOTIFICATIONS_ALL, notifications, GROWL_NOTIFICATIONS_DEFAULT, notifications);
}

- (void)connectedToServer:(NSDictionary *)serverInfo {
    [self growlNotifyWithTitle:@"Connected" description:[serverInfo hostNameWithoutLocalSuffix] notificationName:@"Connected to server"];
    self.serverConnectedTo = serverInfo;
    [self updateView];
}

- (void)disconnectedFromServer:(NSDictionary *)serverInfo {
    [self growlNotifyWithTitle:@"Disconnected" description:[serverInfo hostNameWithoutLocalSuffix] notificationName:@"Disconnected from server"];
    self.serverConnectedTo = nil;
    [self updateView];
}

- (void)lostServer:(NSDictionary *)serverInfo {
    [self growlNotifyWithTitle:@"Gone" description:[serverInfo hostNameWithoutLocalSuffix] notificationName:@"Server is gone"];
    [servers removeObject:serverInfo];
    [self updateView];
}

- (void)foundServer:(NSDictionary *)serverInfo {
    [self growlNotifyWithTitle:@"Found" description:[serverInfo hostNameWithoutLocalSuffix] notificationName:@"Server found"];
    [servers addObject:serverInfo];
    [self updateView];
}

- (void)dealloc {
    self.serverConnectedTo = nil;
    
    [servers release];
    
    [serversFoundIcon release];
    [connectedToServerIcon release];
    [noServersFoundIcon release];
    
    [statusItem release];
    [statusItemMenu release];
    [agentStatusMenuItem release];
    
    [tabiAgent release];
    
    [super dealloc];
}

@end
