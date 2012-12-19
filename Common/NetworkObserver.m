#import "NetworkObserver.h"
#import <netinet/in.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <sys/socket.h>
#import "CollectionsAdditions.h"
#import "BlocksAdditions.h"
#import "NetUtils.h"

@implementation NetworkObserver

@synthesize examinedInterfacesAddresses;
@synthesize delegate;

- (id)init {
    if (self == [super init]) {
        reachability = [[NSMutableDictionary alloc] init];
    }
    
    return self;
}

- (void)disableReachability:(SCNetworkReachabilityRef)reachabilityRef {
    SCNetworkReachabilityUnscheduleFromRunLoop(reachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
}

- (NSDictionary *)reachability:(SCNetworkReachabilityRef)reachabilityRef changedWithFlags:(SCNetworkReachabilityFlags) flags {
    NSString *target = (reachabilityRef == internetReachabilityRef) ? @"internet" : (reachabilityRef == localNetworkReachabilityRef) ? @"LAN" : nil;
    assert(nil != target);
    [reachability setValue:[NSNumber numberWithBool:(flags & kSCNetworkReachabilityFlagsReachable)] forKey:target];
    return reachability;
}
    

static void ReachabilityCallback(SCNetworkReachabilityRef targetRef, SCNetworkReachabilityFlags flags, void *info) {
    NetworkObserver *observer = (NetworkObserver *)info;
    NSDictionary *acc = [[observer reachability:targetRef changedWithFlags:flags] copy];
    OnThread([observer validParentThread], NO, ^{
        [observer.delegate reachabilityChanged:acc];
        [acc release];
    });
}

- (NSDate *)dateToRunBefore {
    return [NSDate dateWithTimeIntervalSinceNow:5];
}

- (void)initialize {
    struct sockaddr_in zeroAddress;
    memset(&zeroAddress, 0, sizeof zeroAddress);
    zeroAddress.sin_len = sizeof(zeroAddress);
    zeroAddress.sin_family = AF_INET;
    internetReachabilityRef = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr*)&zeroAddress);
    
    if (!internetReachabilityRef) {
        NSLog(@"netob. Could not create internet reachability");
        shouldStop = YES;
        return;
    }
    
    SCNetworkReachabilityFlags internetFlags;
    BOOL gotInternetFlags = SCNetworkReachabilityGetFlags(internetReachabilityRef, &internetFlags);
    if (gotInternetFlags) {
        [self reachability:internetReachabilityRef changedWithFlags:internetFlags];
    }
    
    struct sockaddr_in localAddress;
    memset(&localAddress, 0, sizeof localAddress);
    localAddress.sin_len = sizeof(localAddress);
    localAddress.sin_family = AF_INET;
    localAddress.sin_addr.s_addr = htonl(IN_LINKLOCALNETNUM); // 169.254.0.0
    localNetworkReachabilityRef = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr*)&localAddress);
   
    if (!localNetworkReachabilityRef) {
        NSLog(@"netob. Could not create LAN reachability");
        shouldStop = YES;
        return;
    }
    
    SCNetworkReachabilityFlags localNetworkFlags;
    BOOL gotLocalNetworkFlags = SCNetworkReachabilityGetFlags(localNetworkReachabilityRef, &localNetworkFlags);
    if (gotLocalNetworkFlags) {
        [self reachability:localNetworkReachabilityRef changedWithFlags:localNetworkFlags];
    }
    
    SCNetworkReachabilityContext ctx = {
        0, self, NULL, NULL, NULL
    };
    if (!SCNetworkReachabilitySetCallback(internetReachabilityRef, ReachabilityCallback, &ctx) || 
        !SCNetworkReachabilitySetCallback(localNetworkReachabilityRef, ReachabilityCallback, &ctx)) {
        NSLog(@"netob. Could register callback for at least one of the reachabilities");
        shouldStop = YES;
        return;
    }
    
    if (!SCNetworkReachabilityScheduleWithRunLoop(internetReachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode) ||
        !SCNetworkReachabilityScheduleWithRunLoop(localNetworkReachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode)) {
        NSLog(@"netob. Could not schedule at least one of the reachabilities in the run loop");
        shouldStop = YES;
        return;
    }
    
    NSDictionary *acc = [reachability copy];
    OnThread([self validParentThread], NO, ^{
        [delegate reachabilityChanged:acc];
        [acc release];
    });
}

- (void)notifyDelegateAboutUpdatedInterfacesAddresses:(NSArray *)updatedInterfaces {
    NSArray *interfaces = [updatedInterfaces copy];
    OnThread([self validParentThread], NO, ^{
        [delegate networkInterfacesWereUpdated:interfaces];
        [interfaces release];
    });
}

- (void)examineInterfacesAddresses {
    NSArray *interfacesAddresses = NetworkInterfaces();
    if (nil == interfacesAddresses) {
        shouldStop = YES;
        return;
    }
    
    if (examinedInterfacesAddresses) {
        if ([examinedInterfacesAddresses count] != [interfacesAddresses count]) {
            self.examinedInterfacesAddresses = interfacesAddresses;
            [self notifyDelegateAboutUpdatedInterfacesAddresses:interfacesAddresses];
            return;
        }
        
        if (nil != [examinedInterfacesAddresses first:^BOOL(id examined) {
            NSString *examinedName = [examined valueForKey:@"name"];
            NSString *examinedAddress = [examined valueForKey:@"address"];
            return nil == [interfacesAddresses first:^(id curr) {
                NSString *currentName = [curr valueForKey:@"name"];
                NSString *currentAddress = [curr valueForKey:@"address"];
                
                if (![currentName isEqualToString:examinedName]) {
                    return NO;
                }
                
                if (nil == examinedAddress && nil == currentAddress) {
                    return YES;
                }
                
                return [examinedAddress isEqualToString:currentAddress];
            }];
        }]) {
            self.examinedInterfacesAddresses = interfacesAddresses;
            [self notifyDelegateAboutUpdatedInterfacesAddresses:interfacesAddresses];
            return;
        }
    }
    else {
        self.examinedInterfacesAddresses = interfacesAddresses;
        [self notifyDelegateAboutUpdatedInterfacesAddresses:interfacesAddresses];
    }
    
//    NSLog(@"netob. Interfaces addresses: %@", interfacesAddresses);
}

- (void)loop {
    [self examineInterfacesAddresses];
}

- (void)cleanup {
    if (NULL != internetReachabilityRef) {
        SCNetworkReachabilityUnscheduleFromRunLoop(internetReachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        CFRelease(internetReachabilityRef);
    }
    if (NULL != localNetworkReachabilityRef) {
        SCNetworkReachabilityUnscheduleFromRunLoop(localNetworkReachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        CFRelease(localNetworkReachabilityRef);
    }
}

- (void)dealloc {
    [reachability release];
    
    self.examinedInterfacesAddresses = nil;
    self.delegate = nil;
    
    [super dealloc];
}

@end
