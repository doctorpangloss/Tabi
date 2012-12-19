#import <sys/types.h>
#import <sys/socket.h>
#import <netdb.h>

enum {
    tInternetIsReachable = 1 << 1,
    tLANIsReachable = 1 << 2,
};

#define tIPv4 @"IPv4"
#define tIPv6 @"IPv6"

typedef uint32_t tNetworkReachabilityFlags;

void * InAddrStruct(struct sockaddr *sa);

NSString * AddressString(struct sockaddr *sa);

NSArray * NetworkInterfaces();

NSString * NetworkOfIPv4Address(NSString *address, NSString *mask);
