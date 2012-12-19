#import "RootViewController.h"
#import "BlocksAdditions.h"
#import "CollectionsAdditions.h"
#import "UIAppUtils.h"

@implementation RootViewController

@synthesize LANIPs;

#define SOCKS_SERVER_PORT 1080
#define LAN_IPS_SECTION 1

- (void)netServiceDidPublish:(NSNetService *)sender {
    NSLog(@"ctrl. Net service published: %@", sender);
}

- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict {
    NSLog(@"ctrl. Net service did not publish: %@", errorDict);
}

- (void)netServiceDidStop:(NSNetService *)sender {
    NSLog(@"ctrl. Net service did stop");
}

- (void)startSOCKSServer {
    if (![LANIPs count]) {
//        showAlert(@"Error", @"Network is not ready yet.");
        return;
    }
    [socksServer start];
}

- (void)stopSOCKSServer {
    if ([socksServer isRunning]) {
        [socksServer stop];
    }
}

- (BOOL)isSOCKSServerRunning {
    return [socksServer isRunning];
}

- (IBAction)switchSOCKSServer:(id)sender {
    [socksServer isRunning] ? [self stopSOCKSServer] : [self startSOCKSServer];
}

- (void)updateInterfaceWithServerRunning:(BOOL)serverRunning {
    socksServerSwitch.on = serverRunning;
    for (int i = 0; i < [LANIPs count]; i++) {
        UITableViewCell *interfaceCell = [tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:LAN_IPS_SECTION]];
        NSString *addr = [LANIPs objectAtIndex:i];
        NSString *labelText = serverRunning ? [NSString stringWithFormat:@"%@:%d", addr, SOCKS_SERVER_PORT] : addr;
        interfaceCell.textLabel.text = labelText;
    }
}

- (void)SOCKSServerCouldNotStart:(SOCKSServer *)server withError:(NSString *)err {
    NSLog(@"ctrl. Could not start SOCKS server: %@", err);
    [self updateInterfaceWithServerRunning:NO];
    showAlert(@"Error", [NSString stringWithFormat:@"Could not start SOCKS server: %@.", err]);
}

- (void)SOCKSServerDidStart:(SOCKSServer *)server {
//    NSLog(@"ctrl. SOCKS server did start");
    [self updateInterfaceWithServerRunning:YES];

    NSDictionary *dict = $dict(@"udid", [[UIDevice currentDevice] uniqueIdentifier],);
    if (![netService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:dict]]) {
        NSLog(@"ctrl. Could not set TXT data");
    }
    
    [netService publish];
}

- (void)SOCKSServerDidStop:(SOCKSServer *)server {
    NSLog(@"ctrl. SOCKS server did stop");
    [netService stop];
    [self updateInterfaceWithServerRunning:NO];
}

- (void)updateNetworkInterfacesHeaderWithLabelText:(NSString *)text andWaitingIndication:(BOOL)waiting animated:(BOOL)animated {
    CGSize labelSize = [text sizeWithFont:LANIPsHeaderLabel.font];
    CGRect labelFrame = CGRectMake(LANIPsHeaderLabel.frame.origin.x, 
                                   LANIPsHeaderLabel.frame.origin.y,
                                   labelSize.width, 
                                   labelSize.height);
    BasicBlock interfaceUpdateBlock = ^{
        LANIPsHeaderLabel.alpha = 0;

        LANIPsHeaderLabel.frame = labelFrame;
        LANIPsHeaderLabel.text = text;
        
        interfacesLookupIndicator.frame = CGRectMake(labelFrame.origin.x + labelFrame.size.width + 5, labelFrame.origin.y, interfacesLookupIndicator.frame.size.width, interfacesLookupIndicator.frame.size.height);
        waiting ? [interfacesLookupIndicator startAnimating] : [interfacesLookupIndicator stopAnimating];

        LANIPsHeaderLabel.alpha = 1;
    };
    
    if (animated) {
        [UIView beginAnimations:@"frame" context:nil];
        interfaceUpdateBlock();
        [UIView commitAnimations];
        return;
    }
    
    interfaceUpdateBlock();
}

- (NSString *)LANIPsHeaderTextWithAvailableIPsCount:(NSUInteger)count {
    return 0 == count ? @"Waiting for network..." : 1 == count ? @"Address to connect to:" : @"Addresses to connect to:";
}

- (void)reachabilityChanged:(NSDictionary *)reachability {
    NSLog(@"ctrl. Reachability changed: %@", reachability);
}

// TODO: Switch to Reachability for LAN readiness detection
- (void)networkInterfacesWereUpdated:(NSArray *)newInterfaces {
    // Working only with IPv4 for now
    NSArray *LANInterfaces = [newInterfaces grep:^BOOL(id interface) {
        NSString *addrFamily = [interface valueForKey:@"addressFamily"];
        if (![tIPv4 isEqualToString:addrFamily]) {
            return NO;
        }
        
        NSString *addr = [interface valueForKey:@"address"];
        if (nil == addr || [@"" isEqualToString:addr]) {
            return NO;
        }
        NSString *name = [interface valueForKey:@"name"];
        return NSOrderedSame == [name compare:@"en" options:NSCaseInsensitiveSearch range:NSMakeRange(0, 2)];
    }];
    
    NSLog(@"ctrl. LAN interfaces: %@", LANInterfaces);
    NSArray *newLANIPs = [[LANInterfaces sort:^NSComparisonResult(id a, id b) {
        NSString *aName = [a valueForKey:@"name"];
        NSString *bName = [b valueForKey:@"name"];
        
        return [aName compare:bName options:NSCaseInsensitiveSearch];
    }] map:^id(id interface) {
        return [interface valueForKey:@"address"];
    }];
    
    if ([LANIPs isEqual:newLANIPs]) {
        return;
    }
    
//    NSLog(@"ctrl. New LAN IPs: %@", newLANIPs);
    
    if (0 != [newLANIPs count]) {
        socksServerSwitch.enabled = YES;
        [self updateNetworkInterfacesHeaderWithLabelText:[self LANIPsHeaderTextWithAvailableIPsCount:[newLANIPs count]] andWaitingIndication:NO animated:NO];

        if (![socksServer isRunning]) {
            [socksServer start];
        }
    }
    else {
        socksServerSwitch.enabled = NO;
        [self updateNetworkInterfacesHeaderWithLabelText:[self LANIPsHeaderTextWithAvailableIPsCount:[newLANIPs count]] andWaitingIndication:YES animated:NO];
        
        if ([socksServer isRunning]) {
            [socksServer stop];
        }
    }
    
    // Smooth animation :-)
    NSMutableArray *indexesToDelete = [NSMutableArray array];
    [LANIPs forEachDo:^(id oldIP, NSUInteger idx) {
        if (nil == [newLANIPs first:^BOOL(id newIP) { return newIP == oldIP; }]) {
            [indexesToDelete addObject:[NSIndexPath indexPathForRow:idx inSection:LAN_IPS_SECTION]];
        }
    }];
    
    [tableView beginUpdates];
    if ([indexesToDelete count]) {
        [tableView deleteRowsAtIndexPaths:indexesToDelete withRowAnimation:UITableViewRowAnimationFade];
    }
    
    NSMutableArray *indexesToInsert = [NSMutableArray array];
    [newLANIPs forEachDo:^(id newIP, NSUInteger idx) {
        if (nil == [LANIPs first:^BOOL(id oldIP) { return oldIP == newIP; }]) {
            [indexesToInsert addObject:[NSIndexPath indexPathForRow:idx inSection:LAN_IPS_SECTION]];
        }
    }];
    
    self.LANIPs = newLANIPs;
    if ([indexesToInsert count]) {
        [tableView insertRowsAtIndexPaths:indexesToInsert withRowAnimation:UITableViewRowAnimationFade];
    }
    [tableView endUpdates];
    // End of smooth animation
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (LAN_IPS_SECTION == section) {
        return LANIPsHeader;
    }
    
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (LAN_IPS_SECTION == section) {
        return LANIPsHeader.frame.size.height;
    }
    
    return 44;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (0 == section) {
        return @"Server will shutdown if you close this\n\
application. You can still lock the screen,\n\
but make sure your device is connected\n\
to power source.";
    }
    
    return nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.modalViewController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    
    self.title = @"Tabi";
    tableView.allowsSelection = NO;

    self.LANIPs = [NSArray array];
    socksServer = [[SOCKSServer alloc] initWithPort:SOCKS_SERVER_PORT];
    socksServer.delegate = self;

    networkObserver = [[NetworkObserver alloc] init];
    networkObserver.delegate = self;
    [networkObserver start];
    
    NSString *publishingName = [NSString stringWithFormat:@"Tabi SOCKS5 Server %@", [[UIDevice currentDevice] uniqueIdentifier]];
    netService = [[NSNetService alloc] initWithDomain:@"local." type:@"_socks5._tcp" name:publishingName port:SOCKS_SERVER_PORT];
    [netService setDelegate:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    LANIPsHeader.backgroundColor = [UIColor clearColor];
    LANIPsHeaderLabel.textColor = [UIColor darkGrayColor];
    LANIPsHeaderLabel.shadowColor = [UIColor whiteColor];
    LANIPsHeaderLabel.shadowOffset = CGSizeMake(.0, 1.0);
    LANIPsHeaderLabel.font = [UIFont boldSystemFontOfSize:17];
    
    [self updateNetworkInterfacesHeaderWithLabelText:[self LANIPsHeaderTextWithAvailableIPsCount:[LANIPs count]] andWaitingIndication:0 == [LANIPs count] animated:NO];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (void)viewDidUnload {
    [super viewDidUnload];
}


#pragma mark Table view methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)aTableView {
    return 2;
}


// Customize the number of rows in the table view.
- (NSInteger)tableView:(UITableView *)aTableView numberOfRowsInSection:(NSInteger)section {
    if (0 == section) {
        return 1;
    }
    else if (LAN_IPS_SECTION == section) {
        return [LANIPs count];
    }
    
    return 0;
}

// Customize the appearance of table view cells.
- (UITableViewCell *)tableView:(UITableView *)aTableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (0 == indexPath.row && 0 == indexPath.section) {
        socksServerSwitch.enabled = 0 != [self.LANIPs count];
        socksServerSwitch.on = [socksServer isRunning];
        return socksServerControlCell;
    }
    
    static NSString *cellIdentifier = @"Cell";
    UITableViewCell *cell = [aTableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier] autorelease];
    }
    
    
    if (LAN_IPS_SECTION == indexPath.section) {
        NSString *ip = [LANIPs objectAtIndex:indexPath.row];
        cell.textLabel.text = [socksServer isRunning] ? [NSString stringWithFormat:@"%@:%d", ip, SOCKS_SERVER_PORT] : ip;
    }
    
    return cell;
}

- (void)dealloc {
    [tableView release];
    [socksServer release];
    [networkObserver release];
    
    [socksServerControlCell release];
    [socksServerLabel release];
    [interfacesLookupIndicator release];
    [LANIPsHeaderLabel release];
    [socksServerSwitch release];
    [LANIPsHeader release];
    
    self.LANIPs = nil;

    [super dealloc];
}


@end

