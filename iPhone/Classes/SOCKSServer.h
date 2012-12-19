#import <Foundation/Foundation.h>
#import "Actor.h"


@class SOCKSConnection;
@class SOCKSServer;

@protocol SOCKSServerDelegate

- (void)SOCKSServerCouldNotStart:(SOCKSServer *)server withError:(NSString *)err;
- (void)SOCKSServerDidStart:(SOCKSServer *)server;
- (void)SOCKSServerDidStop:(SOCKSServer *)server;

@end

@protocol SOCKSConnectionDelegate

- (void)connectionDidBecomeInvalid:(SOCKSConnection *)conn;
- (void)connectionDidClose:(SOCKSConnection *)conn;
- (void)TCPConnectionWithTargetHostEstablished:(SOCKSConnection *)conn;

@end


@interface SOCKSServer : Actor<SOCKSConnectionDelegate> {
    id<SOCKSServerDelegate> delegate;
    
    uint16_t port;
    CFSocketRef ipv4Socket;
    CFSocketRef ipv6Socket;
    
    NSMutableArray *connections;
}

@property (nonatomic, retain) id<SOCKSServerDelegate> delegate;
@property (nonatomic) uint16_t port;

- (id)initWithPort:(uint16_t)initPort;
- (void)connectionDidClose:(SOCKSConnection *)conn;


@end
