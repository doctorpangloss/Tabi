//
//  TabiAgent.h
//  Tabi_Mac_OS_X
//
//  Created by Vyacheslav Zakovyrya on 2/20/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Actor.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import "NetworkObserver.h"
#import "NSDictionaryAdditions.h"

@protocol TabiAgentDelegate

- (void)connectedToServer:(NSDictionary *)serverInfo;
- (void)disconnectedFromServer:(NSDictionary *)serverInfo;
- (void)lostServer:(NSDictionary *)serverInfo;
- (void)foundServer:(NSDictionary *)serverInfo;

@end


@interface TabiAgent : Actor<NetworkObserverDelegate, NSNetServiceDelegate, NSNetServiceBrowserDelegate> {
    SCPreferencesRef systemPreferences;
    AuthorizationRef systemAuthorization;
    
    NSMutableArray *serversFound;
    NSMutableDictionary *serverConnectedTo;
    
    NSNetServiceBrowser *netServiceBrowser;
    NetworkObserver *networkObserver;
    
    id<TabiAgentDelegate> delegate;
}

@property (nonatomic, retain) NSMutableDictionary *serverConnectedTo;
@property (nonatomic, retain) NSMutableArray *serversFound;

@property (nonatomic, retain) NSNetServiceBrowser *netServiceBrowser;
@property (nonatomic, retain) NetworkObserver *networkObserver;

@property (nonatomic, retain) id<TabiAgentDelegate> delegate;

- (void)requestDisconnectionFromServer:(NSDictionary *)serverInfo shouldWait:(BOOL)shouldWait;
- (void)requestConnectionToServer:(NSDictionary *)serverInfo;

@end
