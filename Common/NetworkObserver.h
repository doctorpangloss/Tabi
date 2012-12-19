#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import "Actor.h"
#import "NetUtils.h"

@protocol NetworkObserverDelegate

- (void)networkInterfacesWereUpdated:(NSArray *)newInterfaces;
- (void)reachabilityChanged:(NSDictionary *)reachability;

@end


@interface NetworkObserver : Actor {
    SCNetworkReachabilityRef internetReachabilityRef;
    SCNetworkReachabilityRef localNetworkReachabilityRef;
    
    tNetworkReachabilityFlags networkReachability;
    
    NSArray *examinedInterfacesAddresses;
    
    NSMutableDictionary *reachability;
    
    id<NetworkObserverDelegate> delegate;
}

@property (nonatomic, retain) NSArray *examinedInterfacesAddresses;
@property (nonatomic, retain) id<NetworkObserverDelegate> delegate;

@end
