//
//  TabiAgent.m
//  Tabi_Mac_OS_X
//
//  Created by Vyacheslav Zakovyrya on 2/20/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "TabiAgent.h"

#import "NetUtils.h"
#import "CollectionsAdditions.h"
#import "BlocksAdditions.h"
#import "NSAppUtils.h"

#define RESOLVE_TIMEOUT 15


@interface NSNetService(TabiAdditions)

@end

@implementation NSNetService(TabiAdditions)

- (NSArray *)addressesAsArrayOfStrings {
    return [[self addresses] map:^id(id addrData) {
        struct sockaddr *sockaddr = (struct sockaddr *)[addrData bytes];
        NSString *addressStr = AddressString(sockaddr);
        return   addressStr;
    }];
}

- (void)getLocalNetworkInterfaceBSDName:(NSString **)interfaceName toConnectToServiceAddress:(NSString **)serviceAddress {
    NSArray *serviceAddresses = [self addressesAsArrayOfStrings];
    NSArray *networkInterfaces = NetworkInterfaces();
    //    NSLog(@"network interfaces: %@", networkInterfaces);
    for (NSDictionary *interfaceDict in networkInterfaces) {
        NSString *iName = [interfaceDict valueForKey:@"name"];
        if ([iName length] > 2 && NSOrderedSame == [iName compare:@"lo" options:NSCaseInsensitiveSearch range:NSMakeRange(0, 2)]) {
            continue;
        }
        if (![tIPv4 isEqualToString:[interfaceDict valueForKey:@"addressFamily"]]) {
            continue;
        }
        NSString *localAddress = [interfaceDict valueForKey:@"address"];
        if (!([localAddress length] > 0)) {
            continue;
        }
        NSString *maskAddress = [interfaceDict valueForKey:@"netMask"];
        if (!([maskAddress length] > 0)) {
            continue;
        }
        
        NSString *localNetworkAddress = NetworkOfIPv4Address(localAddress, maskAddress);
        if (nil == localNetworkAddress) {
            continue;
        }
        
        
        *serviceAddress = [serviceAddresses first:^BOOL(id srvAddr) {
            return [localNetworkAddress isEqualToString:NetworkOfIPv4Address(srvAddr, maskAddress)];
        }];
        
        *interfaceName = iName;
        return;
    }
}

@end


@implementation TabiAgent

@synthesize serverConnectedTo, serversFound;
@synthesize netServiceBrowser, networkObserver;
@synthesize delegate;

static BOOL IsConnectedToServer(NSDictionary *networkServicesPrefs, NSDictionary *serverInfo) {
    NSString *interfaceID = [serverInfo valueForKey:@"localNetworkInterfaceIDToConnectFrom"];
    NSDictionary *proxySettings = [networkServicesPrefs valueForKeyPath:[NSString stringWithFormat:@"%@.Proxies", interfaceID]];
    if (nil == proxySettings) {
        return NO;
    }
    NSNumber *SOCKSEnable = [proxySettings valueForKey:@"SOCKSEnable"];
    if (nil == SOCKSEnable) {
        return NO;
    }
    NSNumber *SOCKSPort = [proxySettings valueForKey:@"SOCKSPort"];
    if (nil == SOCKSPort) {
        return NO;
    }
    
    NSString *serverAddress = [serverInfo valueForKey:@"serverAddressToConnectTo"];
    NSNumber *serverPort = [serverInfo valueForKey:@"serverPort"];
    
    return [[NSNumber numberWithInt:1] isEqualToNumber:SOCKSEnable] && [serverAddress isEqualToString:[proxySettings valueForKey:@"SOCKSProxy"]] && [serverPort isEqualToNumber:SOCKSPort];
}

static BOOL DoWithSynchAndLockedPrefs(SCPreferencesRef prefs, BOOL(^block)()) {
    SCPreferencesSynchronize(prefs);
    if (!SCPreferencesLock(prefs, NO)) {
        // Beep?
        NSLog(@"could not lock system preferences");
        return NO;
    }
    NSLog(@"locked system preferences");
    
    BOOL success = block();
    
    if (SCPreferencesUnlock(prefs)) {
        NSLog(@"unlocked system preferences");
    }
    else {
        NSLog(@"could not unlock system preferences");
    }
    
    return success;
}

static BOOL SetNetworkPreferences(SCPreferencesRef prefs, NSMutableDictionary *(^newPrefsBlock)(NSMutableDictionary *currentNetworkServicesPrefs)) {
    return DoWithSynchAndLockedPrefs(prefs, ^{
        NSMutableDictionary *currentNetworkServicesPrefs = (NSMutableDictionary *)SCPreferencesGetValue(prefs, kSCPrefNetworkServices);
        NSMutableDictionary *newNetworkServicesPrefs = newPrefsBlock(currentNetworkServicesPrefs);
        if (nil != newNetworkServicesPrefs) {
            if (!SCPreferencesSetValue(prefs, kSCPrefNetworkServices, newNetworkServicesPrefs) || !SCPreferencesCommitChanges(prefs) || !SCPreferencesApplyChanges(prefs)) {
                NSError *err = [(NSError *) SCCopyLastError() autorelease];
                NSLog(@"could not set new network preferences: %@", [err localizedDescription]);
            }
            else {
                NSLog(@"new network preferences are set");
                return YES;
            }
        }
        return NO;
    });
}

static BOOL SetNetworkInterfaceProxySettings(SCPreferencesRef prefs, NSString *interfaceID, NSMutableDictionary *(^newSettingsBlock)(NSMutableDictionary *currentSettings)) {
    return SetNetworkPreferences(prefs, ^NSMutableDictionary *(NSMutableDictionary *currentNetworkPrefs) {
        if (nil == [currentNetworkPrefs valueForKey:interfaceID]) {
            NSLog(@"could not find network interface with ID %@ to connect to Tabi server", interfaceID);
            return nil;
        }
        NSString *proxySettingsKeyPath = [NSString stringWithFormat:@"%@.Proxies", interfaceID];
        NSMutableDictionary *currentProxySettings = [currentNetworkPrefs valueForKeyPath:proxySettingsKeyPath];
        if (nil == currentProxySettings) {
            NSLog(@"could not find proxy settings for interface %@", interfaceID);
            return nil;
        }
        NSLog(@"current proxy settings for interface %@: %@", interfaceID, currentProxySettings);
        NSMutableDictionary *newProxySettings = newSettingsBlock(currentProxySettings);
        if (nil == newProxySettings) {
            return nil;
        }
        NSLog(@"new proxy settings for interface %@: %@", interfaceID, newProxySettings);
        [currentNetworkPrefs setValue:newProxySettings forKeyPath:proxySettingsKeyPath];
        
        return currentNetworkPrefs;
    });
}

- (NSMutableDictionary *)findServerConnectedTo {
    __block NSMutableDictionary *serverConnectedToInfo = nil;
    DoWithSynchAndLockedPrefs(systemPreferences, ^BOOL {
        NSDictionary *networkServicesPrefs = (NSDictionary *)SCPreferencesGetValue(systemPreferences, kSCPrefNetworkServices);
        
        serverConnectedToInfo = [serversFound first:^BOOL (id serverInfo) {
            return IsConnectedToServer(networkServicesPrefs, serverInfo);
        }];
        return YES;
    });
    
    return serverConnectedToInfo;
}

static NSDictionary* NotificationCopyOfServerInfo(NSDictionary *serverInfo) {
    return $dict(@"hostName", [serverInfo valueForKey:@"hostname"], 
                 @"serverPort", [serverInfo valueForKey:@"serverPort"],
                 @"serverAddressToConnectTo", [serverInfo valueForKey:@"serverAddressToConnectTo"],
                 @"localNetworkInterfaceIDToConnectFrom", [serverInfo valueForKey:@"localNetworkInterfaceIDToConnectFrom"]);
}

- (void)callDelegateSelector:(SEL)sel withServerInfo:(NSDictionary *)serverInfo {
    NSDictionary *copy = NotificationCopyOfServerInfo(serverInfo);
    OnThread([self validParentThread], NO, ^{
        [(NSObject *)delegate performSelector:sel withObject:copy];
    });
}

- (NSMutableDictionary *)serverInfoByNetService:(NSNetService *)netService {
    return [serversFound first:^BOOL(id info) {
        return [netService isEqualTo:[info valueForKey:@"netService"]];
    }];
}

- (void)updateServerConnections {
    NSLog(@"updating \"connections\"...");
    NSMutableDictionary *serverWasConnectedTo = [[self.serverConnectedTo retain] autorelease];
    self.serverConnectedTo = [self findServerConnectedTo];
    NSLog(@"was connected to %@, now connected to: %@", serverWasConnectedTo, serverConnectedTo);
    
    if (serverWasConnectedTo == serverConnectedTo) {
        return;
    }
    
    if (nil != serverWasConnectedTo) {
        [self callDelegateSelector:@selector(disconnectedFromServer:) withServerInfo:serverWasConnectedTo];
    }
    if (nil != serverConnectedTo) {
        [self callDelegateSelector:@selector(connectedToServer:) withServerInfo:serverConnectedTo];
    }
}

- (void)updateServerInfo:(NSMutableDictionary *)serverInfo {
    NSNetService *netService = [serverInfo valueForKey:@"netService"];
    
    NSString *networkInterfaceBSDName = nil;
    NSString *netServiceAddressToConnectTo = nil;
    [netService getLocalNetworkInterfaceBSDName:&networkInterfaceBSDName toConnectToServiceAddress:&netServiceAddressToConnectTo];
    if (nil == networkInterfaceBSDName) {
        NSLog(@"could not determine BSD name of interface to connect to Tabi server");
        return;
    }
    if (nil == netServiceAddressToConnectTo) {
        NSLog(@"could not determine service address to connect to");
        return;
    }
    
    SCPreferencesSynchronize(systemPreferences);
    NSMutableDictionary *prefNetworkServices = (NSMutableDictionary *)SCPreferencesGetValue(systemPreferences, kSCPrefNetworkServices);
    NSString *interfaceID = [[prefNetworkServices allKeys] first:^BOOL(id interfaceID) {
        return [networkInterfaceBSDName isEqualToString:[prefNetworkServices valueForKeyPath:[NSString stringWithFormat:@"%@.Interface.DeviceName", interfaceID]]];
    }];
    
    
    [serverInfo setValue:[netService hostName] forKey:@"hostname"];
    [serverInfo setValue:[NSNumber numberWithInt:[netService port]] forKey:@"serverPort"];
    [serverInfo setValue:netServiceAddressToConnectTo forKey:@"serverAddressToConnectTo"];
    [serverInfo setValue:interfaceID forKey:@"localNetworkInterfaceIDToConnectFrom"];
}

- (void)reachabilityChanged:(NSDictionary *)reachability {
    //    NSLog(@"reachability changed: %@", reachability);
}

- (void)connectToServer:(NSDictionary *)serverInfo {
    NSLog(@"connecting to Tabi server %@...", serverInfo);
    NSString *interfaceID = [serverInfo valueForKey:@"localNetworkInterfaceIDToConnectFrom"];
    
    SetNetworkInterfaceProxySettings(systemPreferences, interfaceID, ^NSMutableDictionary *(NSMutableDictionary *currentProxySettings) {
        if (nil == [defaults valueForKeyPath:[NSString stringWithFormat:@"prevProxySettingsForLocalInterfaces.%@", interfaceID]]) { // initial settings
            NSLog(@"saving current proxy settings: %@ for interface: %@ in defaults", currentProxySettings, interfaceID);
            NSMutableDictionary *newDict = [NSMutableDictionary dictionaryWithDictionary:[defaults dictionaryForKey:@"prevProxySettingsForLocalInterfaces"]];
            [newDict setValue:[NSKeyedArchiver archivedDataWithRootObject:currentProxySettings] forKey:interfaceID];
            [defaults setValue:newDict forKey:@"prevProxySettingsForLocalInterfaces"];
            [NSUserDefaults resetStandardUserDefaults];
        }
        
        NSMutableDictionary *newProxySettings = [[currentProxySettings mutableCopy] autorelease];
        
        NSNumber *yes = [NSNumber numberWithInt:1];
        [newProxySettings setValue:yes forKey:@"SOCKSEnable"];
        [newProxySettings setValue:yes forKey:@"FTPPassive"];
        [newProxySettings setValue:[serverInfo valueForKey:@"serverPort"] forKey:@"SOCKSPort"];
        [newProxySettings setValue:[serverInfo valueForKey:@"serverAddressToConnectTo"] forKey:@"SOCKSProxy"];
        
        return newProxySettings;
    });
}

- (void)disconnectFromServer:(NSDictionary *)serverInfo {
    NSLog(@"disconnecting from Tabi server: %@...", serverInfo);
    NSString *interfaceID = [serverInfo valueForKey:@"localNetworkInterfaceIDToConnectFrom"];
    
    BOOL success = SetNetworkInterfaceProxySettings(systemPreferences, interfaceID, ^NSMutableDictionary *(NSMutableDictionary *currentProxySettings) {
        NSData *prevProxyData = [defaults valueForKeyPath:[NSString stringWithFormat:@"prevProxySettingsForLocalInterfaces.%@", interfaceID]];
        if (nil != prevProxyData) {
            return [NSKeyedUnarchiver unarchiveObjectWithData:prevProxyData];
        }
        
        NSMutableDictionary *newProxySettings = [[currentProxySettings mutableCopy] autorelease];
        
        NSNumber *no = [NSNumber numberWithInt:0];
        [newProxySettings setValue:no forKey:@"SOCKSEnable"];        
        return newProxySettings;
    });
    if (success) {
        NSMutableDictionary *newPrevProxySettings = [NSMutableDictionary dictionaryWithDictionary:[defaults dictionaryForKey:@"prevProxySettingsForLocalInterfaces"]];
        [newPrevProxySettings removeObjectForKey:interfaceID];
        [defaults setValue:newPrevProxySettings forKey:@"prevProxySettingsForLocalInterfaces"];
        [NSUserDefaults resetStandardUserDefaults];
    }
}

- (void)processAutoConnect {
    NSNumber *autoConnect = [defaults valueForKey:@"shouldAutoConnect"];
    NSLog(@"auto-connect: %@", autoConnect);
    if ([autoConnect boolValue] && nil == serverConnectedTo && [serversFound count]) {
        NSMutableDictionary *serverCanConnectTo = [[serversFound grep:^BOOL(id serverInfo) {
            return [serverInfo canConnect];
        }] lastObject];
        if (nil != serverCanConnectTo) {
            NSLog(@"connecting to first available Tabi Server because of auto-connect: %@...", serverCanConnectTo);
            [self connectToServer:serverCanConnectTo];
        }
    }
}

- (void)networkInterfacesWereUpdated:(NSArray *)newInterfaces {
    NSLog(@"network interfaces updated");
    [serversFound forEachDo:^(id serverInfo, NSUInteger idx) {
        [self updateServerInfo:serverInfo];
    }];
    
    [self updateServerConnections];
    [self processAutoConnect];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
//    if ([@"shouldAutoConnect" isEqualToString:keyPath]) {
//        return;
//    }
}

- (void)setupApplicationPreferences {
    [defaults addObserver:self forKeyPath:@"shouldAutoConnect" options:NSKeyValueObservingOptionNew context:NULL];
    if (nil == [defaults valueForKey:@"prevProxySettingsForLocalInterfaces"]) {
        [defaults setValue:[NSMutableDictionary dictionary] forKey:@"prevProxySettingsForLocalInterfaces"];
    }
}

- (void)processNonGracefulShutdown {
    NSDictionary *prevProxySettings = [defaults valueForKey:@"prevProxySettingsForLocalInterfaces"];
    NSArray *dirtyInterfaces = [prevProxySettings allKeys];
    if ([dirtyInterfaces count]) {
        NSLog(@"application didn't exit properly. Cleaning up...");
        BOOL succes = SetNetworkPreferences(systemPreferences, ^NSMutableDictionary *(NSMutableDictionary *currentNetworkServicesPrefs) {
            [dirtyInterfaces forEachDo:^(id interfaceID, NSUInteger idx) {
                NSData *proxySettingsData = [prevProxySettings valueForKey:interfaceID];
                NSMutableDictionary *proxySettings = [NSKeyedUnarchiver unarchiveObjectWithData:proxySettingsData];
                [currentNetworkServicesPrefs setValue:proxySettings forKeyPath:[NSString stringWithFormat:@"%@.Proxies", interfaceID]];
            }];
            
            return currentNetworkServicesPrefs;
        });
        if (succes) {
            NSLog(@"proxy settings are restored for %@", dirtyInterfaces);
            [defaults setValue:[NSMutableDictionary dictionary] forKey:@"prevProxySettingsForLocalInterfaces"];
            [NSUserDefaults resetStandardUserDefaults];
        }
        else {
            NSLog(@"could not restore previous proxy settings");
        }
    }
}

- (void)preferencesSaved {
    NSLog(@"notification about saved system prefs recevied");
}

- (void)preferencesApplied {
    NSLog(@"notification about applied system prefs received");
    [self updateServerConnections];
}

static void PreferencesChangedCallback(SCPreferencesRef prefs, SCPreferencesNotification notificationType, void *info) {
    TabiAgent *agent = (TabiAgent *)info;
    if (kSCPreferencesNotificationCommit & notificationType) {
        [agent preferencesSaved];
    }
    if (kSCPreferencesNotificationApply & notificationType) {
        [agent preferencesApplied];
    }
}

- (BOOL)readAndRegisterForSystemPreferencesUpdates {
    if (NULL != systemAuthorization) {
        AuthorizationFree(systemAuthorization, kAuthorizationFlagDefaults);
    }
    
    AuthorizationCreate(NULL, NULL, kAuthorizationFlagDefaults, &systemAuthorization);
    AuthorizationItem item = {"system.preferences", 0, NULL, 0};
    AuthorizationRights rights = {1, &item};
    AuthorizationFlags flags = kAuthorizationFlagExtendRights | kAuthorizationFlagInteractionAllowed | kAuthorizationFlagPreAuthorize;
    OSStatus status = AuthorizationCopyRights(systemAuthorization, &rights, kAuthorizationEmptyEnvironment, flags, NULL);
    if (errAuthorizationSuccess != status) {
        NSLog(@"status: %d", status);
        return NO;
    }
    
    // TODO: something when could not preauthorize
    NSLog(@"successfully preauthorized to change system.preferences");
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier]; 
    
    if (NULL != systemPreferences) {
        CFRelease(systemPreferences);
    }
    systemPreferences = SCPreferencesCreateWithAuthorization(NULL, (CFStringRef)bundleID, NULL, systemAuthorization);
    SCPreferencesContext ctx = {0, self, NULL, NULL, NULL};
    if (!SCPreferencesSetCallback(systemPreferences, PreferencesChangedCallback, &ctx)) {
        NSLog(@"could not set callback");
        return NO;
    }
    
    if (!SCPreferencesScheduleWithRunLoop(systemPreferences, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode)) {
        NSLog(@"could not schedule callback in run loop");
        return NO;
    }
    
    return YES;
}

- (void)requestDisconnectionFromServer:(NSDictionary *)serverInfo shouldWait:(BOOL)shouldWait {
    OnThread(workerThread, shouldWait, ^{
        [self disconnectFromServer:serverInfo];
    });
}

- (void)requestConnectionToServer:(NSDictionary *)serverInfo {
    OnThread(workerThread, NO, ^{
        [self connectToServer:serverInfo];
    });
}

- (void)setupServiceBrowser {
    self.netServiceBrowser = [[[NSNetServiceBrowser alloc] init] autorelease];
    [netServiceBrowser setDelegate:self];
    [netServiceBrowser searchForServicesOfType:@"_socks5._tcp" inDomain:@"local."];
}

- (void)initialize {
    if (![self readAndRegisterForSystemPreferencesUpdates]) {
        shouldStop = YES;
        return;
    }
    
    [self setupApplicationPreferences];
    [self processNonGracefulShutdown];
    
    self.serversFound = [[[NSMutableArray alloc] init] autorelease];
    
    self.networkObserver = [[[NetworkObserver alloc] init] autorelease];
    [networkObserver setDelegate:self];
    [networkObserver start];
    
    [self setupServiceBrowser];
}

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict {
    NSLog(@"did not resolve: %@", errorDict);
}

- (void)netServiceDidStop:(NSNetService *)sender {
    NSLog(@"service %@ resolution did stop", [sender name]);
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didNotSearch:(NSDictionary *)errorInfo {
    NSLog(@"service search stopped: %@", errorInfo);
}

- (void)netServiceBrowserWillSearch:(NSNetServiceBrowser *)netServiceBrowser {
    NSLog(@"service search started...");
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didFindService:(NSNetService *)aNetService moreComing:(BOOL)moreServicesComing {
    NSLog(@"found service: %@. Resolving with timeout: %d. More coming: %d", [aNetService name], RESOLVE_TIMEOUT, moreServicesComing);
    
    [aNetService setDelegate:self];
    [aNetService resolveWithTimeout:RESOLVE_TIMEOUT];
    
    [serversFound addObject:$mdict(@"netService", aNetService)];
}

- (void)netServiceDidResolveAddress:(NSNetService *)sender {
    [sender stop]; // Don't need to continue resolution for this service anymore
    
    NSLog(@"did resolve address for service: %@", [sender name]);
    NSLog(@"hostname: %@, port: %d, addresses: %@", [sender hostName], [sender port], [sender addressesAsArrayOfStrings]);
    
    [sender startMonitoring];
    NSMutableDictionary *serverInfo = [self serverInfoByNetService:sender];
    if (nil == serverInfo) {
        NSLog(@"could not find Tabi server info for service: %@", serverInfo);
        return;
    }
    
    [serverInfo setValue:sender forKey:@"netService"];
    [self updateServerInfo:serverInfo];
    
    if ([serverInfo canConnect]) {
        NSLog(@"found Tabi server: %@", serverInfo);
        [self callDelegateSelector:@selector(foundServer:) withServerInfo:serverInfo];
    }
}

- (void)netService:(NSNetService *)sender didUpdateTXTRecordData:(NSData *)data {
    NSLog(@"net service did update TXT rec data: %@", data);
    NSDictionary *dict = [NSNetService dictionaryFromTXTRecordData:[sender TXTRecordData]];
    
    NSString *udid = [NSString stringWithCString:[[dict valueForKey:@"udid"] bytes] encoding:NSUTF8StringEncoding];
    NSLog(@"udid: %@", udid);
    NSMutableDictionary *serverInfo = [self serverInfoByNetService:sender];
    if (nil == serverInfo) {
        NSLog(@"could not find Tabi server info for net service which just updated its TXT rec data: %@", sender);
        return;
    }
    [serverInfo setValue:udid forKey:@"UDID"];
    
    if (1 == [serversFound count] && nil == serverConnectedTo) { // it might be connected manually
        self.serverConnectedTo = [self findServerConnectedTo];
    }
    
    [self processAutoConnect];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didRemoveService:(NSNetService *)netService moreComing:(BOOL)moreServicesComing {
    NSMutableDictionary *serverInfo = [self serverInfoByNetService:netService];
    if (nil == serverInfo) {
        NSLog(@"could not find Tabi Server info for removed NetService!");
        return;
    }
    
    NSLog(@"Tabi server is gone: %@", serverInfo);
    [netService stopMonitoring];
    if (serverInfo == serverConnectedTo) {
        [self disconnectFromServer:serverInfo];
    }
    
    [[serverInfo retain] autorelease];
    [serversFound removeObject:serverInfo];
    
    [self callDelegateSelector:@selector(lostServer:) withServerInfo:serverInfo];
}

- (void)dealloc {
    self.serverConnectedTo = nil;
    self.serversFound = nil;
    
    if (NULL != systemAuthorization) {
        AuthorizationFree(systemAuthorization, kAuthorizationFlagDefaults);
    }
    if (NULL != systemPreferences) {
        CFRelease(systemPreferences);
    }
    
    self.networkObserver = nil;
    self.netServiceBrowser = nil;
    self.delegate = nil;
    
    [super dealloc];
}

@end
