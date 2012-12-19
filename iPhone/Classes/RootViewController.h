#import "SOCKSServer.h"
#import "NetworkObserver.h"

@interface RootViewController : UIViewController<SOCKSServerDelegate, NetworkObserverDelegate, NSNetServiceDelegate> {
    NetworkObserver *networkObserver;
    SOCKSServer *socksServer;
    NSNetService *netService;
    
    NSArray *LANIPs;
    
    IBOutlet UITableView *tableView;
    IBOutlet UITableViewCell *socksServerControlCell;
    IBOutlet UISwitch *socksServerSwitch;
    IBOutlet UILabel *socksServerLabel, *LANIPsHeaderLabel;
    IBOutlet UIView *LANIPsHeader;
    IBOutlet UIActivityIndicatorView *interfacesLookupIndicator;
}

@property (nonatomic, retain) NSArray *LANIPs;

- (IBAction)switchSOCKSServer:(id)sender;
- (void)startSOCKSServer;
- (void)stopSOCKSServer;
- (BOOL)isSOCKSServerRunning;

@end
