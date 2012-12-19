#import "SOCKSServer.h"
#import <CFNetwork/CFNetwork.h>
#import "CollectionsAdditions.h"
#import "BlocksAdditions.h"

#import <netdb.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <unistd.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>


@interface SOCKSConnection : Actor<NSStreamDelegate> {
    id<SOCKSConnectionDelegate>delegate;

    NSString *clientHost, *targetHost;
    NSUInteger clientPort, targetPort;

    NSInputStream *clientInputStream, *targetInputStream;
    NSOutputStream *clientOutputStream, *targetOutputStream;
    
    BOOL isValid;
    
    NSMutableData *toClientData, *toTargetData;
    
    SEL nextActionOnClientInput;
}


@property (setter=valid:) BOOL isValid;
@property (nonatomic, retain) id<SOCKSConnectionDelegate> delegate;
@property (nonatomic, retain) NSString *clientHost, *targetHost;
@property (nonatomic) NSUInteger clientPort, targetPort;
@property (nonatomic, retain) NSInputStream *clientInputStream, *targetInputStream;
@property (nonatomic, retain) NSOutputStream *clientOutputStream; 
@property (nonatomic, retain) NSOutputStream *targetOutputStream;

@property (nonatomic, retain) NSMutableData *toClientData, *toTargetData;


- (id)initWithClientHost:(NSString *)host clientPort:(NSUInteger)port inputStream:(NSInputStream *)input outputStream:(NSOutputStream *)output;

- (void)establishConnectionWithTarget;

@end


@implementation SOCKSConnection

@synthesize delegate;
@synthesize clientHost, targetHost, clientPort, targetPort;
@synthesize clientInputStream, clientOutputStream;
@synthesize targetInputStream, targetOutputStream;
@synthesize toClientData, toTargetData;
@synthesize isValid;

- (id)initWithClientHost:(NSString *)host clientPort:(NSUInteger)port inputStream:(NSInputStream *)input outputStream: (NSOutputStream *)output {
    if (self = [super init]) {
        self.clientHost = host;
        self.clientPort = port;
        
        self.clientInputStream = input;
        self.clientOutputStream = output;
        
        self.toClientData = [NSMutableData data];
        self.toTargetData = [NSMutableData data];
        
        nextActionOnClientInput = @selector(handshake);
    }
    
    return self;
}

- (NSString *)connectionStr {
    return [NSString stringWithFormat:@"%@:%d -> %@:%d", clientHost, clientPort, targetHost, targetPort];
}

- (void)setupInputStream:(NSInputStream *)inputStream outputStream:(NSOutputStream *)outputStream {
    [inputStream setDelegate:self];
    [outputStream setDelegate:self];
    
    [inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    
    // run in background
    [inputStream setProperty:NSStreamNetworkServiceTypeVoIP forKey:NSStreamNetworkServiceType];
    [outputStream setProperty:NSStreamNetworkServiceTypeVoIP forKey:NSStreamNetworkServiceType];
    
    [inputStream open];
    [outputStream open];
}

- (void)initialize {
    [self setupInputStream:clientInputStream outputStream:clientOutputStream];
    isValid = YES;
}

- (void)invalidate {
    if (!self.isValid) {
        return;
    }
    
    [clientInputStream close];
    [clientOutputStream close];
    [targetInputStream close];
    [targetOutputStream close];
    
    self.clientInputStream = nil;
    self.clientOutputStream = nil;
    self.targetInputStream = nil;
    self.targetOutputStream = nil;
    self.isValid = NO;
    
    OnThread([self validParentThread], NO, ^{
        [delegate connectionDidBecomeInvalid:self];
    });
}

- (void)loop {
    shouldStop = !isValid;
}

- (void)cleanup {
    [self invalidate];
    
    OnThread([self validParentThread], NO, ^{
        [delegate connectionDidClose:self];
    });
}

#pragma mark -
#pragma mark read/write to/from client, to/from target

# define MAX_BUFFER_SIZE 1024
- (void)readFromStream:(NSInputStream *)input toBuffer:(NSMutableData *)dataBuffer {
    if (!isValid) {
        return;
    }
    
//    NSLog(@"conn. Reading from stream %@, to buffer", input);
    while (([dataBuffer length] < MAX_BUFFER_SIZE) && [input hasBytesAvailable]) {
        uint8_t buffer[MAX_BUFFER_SIZE - [dataBuffer length]];
        NSUInteger bytesRead = [input read:buffer maxLength:sizeof buffer];
//        NSLog(@"conn. %d bytes were read from input stream %@", bytesRead, input);
        if (0 == bytesRead) {
//            NSLog(@"conn. 0 bytes were read. Closing connection");
            [self invalidate]; 
            return;
        }
        if (-1 == bytesRead) {
            NSLog(@"conn. Stream read status: %d, error: %@. Stopping...", 
                  [input streamStatus], 
                  [[input streamError] localizedDescription]);
            [self invalidate];
            return;
        }
        
        [dataBuffer appendBytes:buffer length:bytesRead];        
    }
}

- (void)writeToStream:(NSOutputStream *)output fromBuffer:(NSMutableData *)dataBuffer {
    if (!isValid) {
        return;
    }
    
//    NSLog(@"conn. Writing from buffer to stream %@", output);
    
    while ([dataBuffer length] && [output hasSpaceAvailable]) {
        NSInteger bytesToWrite = [dataBuffer length];
//        NSLog(@"conn. %d bytes to write into output stream %@", bytesToWrite, output);
        NSInteger bytesWrote = [output write:[dataBuffer bytes] maxLength:bytesToWrite];
//        NSLog(@"conn. %d bytes wrote into output stream %@", bytesWrote, output);
        if (0 == bytesWrote) {
//            NSLog(@"conn. 0 bytes were wrote. Closing connection");
            [self invalidate];
            return;
        }
        if (-1 == bytesWrote) {
            NSLog(@"conn. Stream write status: %d, error: %@. Stopping...", 
                  [output streamStatus], 
                  [[output streamError] localizedDescription]);
            [self invalidate];
            return;
        }
        
        [dataBuffer replaceBytesInRange:NSMakeRange(0, bytesWrote) withBytes:NULL length:0];
    }
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)streamEvent {
    if (!isValid) {
        return;
    }
    
    NSString *streamPeer = (aStream == clientInputStream || aStream == clientOutputStream) ? 
                            @"client" : (aStream == targetInputStream || aStream == targetOutputStream) ? 
                            @"target" : nil;
//    NSLog(@"conn. %@ stream: %@ fired event", streamPeer, theStream);
    
    if (NSStreamEventNone == streamEvent) {
//        NSLog(@"conn. %@ stream %@ event none :-O", streamPeer, theStream);
        return;
    }
    if (NSStreamEventOpenCompleted == streamEvent) {
        if (targetInputStream == aStream) {
            NSLog(@"conn. %@ established", [self connectionStr]);
        }
//        NSLog(@"conn. %@ stream %@ open completed", streamPeer, theStream);
        return;
    }
    if (NSStreamEventHasBytesAvailable == streamEvent) {
//        NSLog(@"conn. %@ stream %@ has bytes available", streamPeer, theStream);
        if ((aStream == clientInputStream) && nextActionOnClientInput) {
//            NSLog(@"conn. command op");
            
            [self performSelector:nextActionOnClientInput];
            [self writeToStream:clientOutputStream fromBuffer:toClientData];
            return;
        }
        
//        NSLog(@"conn. proxy op");
        NSOutputStream *output = nil;
        NSMutableData *buffer = nil;
        if (aStream == clientInputStream) {
            output = targetOutputStream;
            buffer = toTargetData;
        }
        else {
            output = clientOutputStream;
            buffer = toClientData;
        }
        
        do {
            [self readFromStream:(NSInputStream *)aStream toBuffer:buffer];
            [self writeToStream:output fromBuffer:buffer];
        } while ([(NSInputStream *)aStream hasBytesAvailable] && [buffer length] < MAX_BUFFER_SIZE);
        
        return;
    }
    
    if (NSStreamEventHasSpaceAvailable == streamEvent) {
        if ((aStream == clientOutputStream) && nextActionOnClientInput) {
//            NSLog(@"conn. command op");
            [self writeToStream:clientOutputStream fromBuffer:toClientData];
            return;
        }
        
//        NSLog(@"conn. proxy op");
//        NSLog(@"conn. %@ stream %@ has space available", streamPeer, theStream);
        NSInputStream *input = nil;
        NSMutableData *buffer = nil;
        if (aStream == clientOutputStream) {
            input = targetInputStream;
            buffer = toClientData;
        }
        else {
            input = clientInputStream;
            buffer = toTargetData;
        }
        do {
            [self writeToStream:(NSOutputStream *)aStream fromBuffer:buffer];
            [self readFromStream:input toBuffer:buffer];
        } while ([(NSOutputStream *)aStream hasSpaceAvailable] && [buffer length]);
        
        return;
    }
    
    if (NSStreamEventEndEncountered == streamEvent) {
//        NSLog(@"conn. %@ stream %@ encountered end. Stopping...", streamPeer, theStream);
        [self invalidate];
        return;
    }
    
    if (NSStreamEventErrorOccurred == streamEvent) {
        NSLog(@"conn. %@ stream %@ error occured. Status: %d, error: %@. Stopping...", streamPeer, aStream, [aStream streamStatus], [[aStream streamError] localizedDescription]);
        [self invalidate];
        return;
    }
}

#pragma mark -
#pragma mark Processing client request. SOCKS Protocol Version 5
- (void)handshake {
    if (!isValid) {
        return;
    }
//    NSLog(@"conn. Handshaking...");
    
    // field 1: SOCKS ver
    uint8_t socksVer;
    if (1 != [clientInputStream read:&socksVer maxLength:1]) {
        NSLog(@"conn. Could not read SOCKS version");
        [self invalidate];
        return;
    }
//    NSLog(@"conn. SOCKS ver: %d", socksVer);
    if (0x05 != socksVer) {
        NSLog(@"conn. Wrong SOCKS version: %d", socksVer);
        [toClientData setData:[NSData dataWithBytes:"\x05\x07" length:2]];
        [self writeToStream:clientOutputStream fromBuffer:toClientData];
        
        [self invalidate];
        return;
    }
    // field 2: Auth methods num
    uint8_t authMethodsNum;
    if (1 != [clientInputStream read:&authMethodsNum maxLength:1]) {
        NSLog(@"conn. Could not read auth methods num");
        [self invalidate];
        return;
    }
//    NSLog(@"conn. Auth methods num: %d", authMethodsNum);
    
    // field 3: Auth methods
    uint8_t authMethods[authMethodsNum];
    if (sizeof(authMethods) != [clientInputStream read:authMethods maxLength:sizeof(authMethods)]) {
        NSLog(@"conn. Could not read auth methods");
        [self invalidate];
        return;
    }
    
    BOOL noAuthMethodSupported = NO;
    for (int i = 0; i < sizeof authMethods; i++) {
//        NSLog(@"conn. Auth method supported: %d", authMethods[i]);
        if (authMethods[i] == 0x00) { // no authentication method
            noAuthMethodSupported = YES;
            break;
        }
    }
    if (!noAuthMethodSupported) {
        NSLog(@"conn. Could not find supported auth method");
        [toClientData setData:[NSData dataWithBytes:"\x05\x07" length:2]];
        [self writeToStream:clientOutputStream fromBuffer:toClientData];
        [self invalidate];
        return;
    }
    
    nextActionOnClientInput = @selector(request);
    [toClientData setData:[NSData dataWithBytes:"\x05\x00" length:2]]; // handshake complete
//    NSLog(@"conn. Response to client: %@", toClientData);
}

BOOL getTargetInfoFromRequestFragment(NSInputStream *inputStream, NSString **host, NSUInteger *port, NSMutableData **fragmentData, NSString **errorStr) {
    // request's field 4: address type
    uint8_t addressType;
    if (1 != [inputStream read:&addressType maxLength:1]) {
        *errorStr = @"Could not read address type";
        return NO;
    }
    NSMutableData *data = [NSMutableData dataWithBytes:&addressType length:1];
    
    // request's field 5: address
    if (0x01 == addressType) { // IPv4 address, 4 bytes
//        NSLog(@"conn. Reading IPv4 address...");
        uint8_t dataBuffer[4];
        if (sizeof(dataBuffer) != [inputStream read:dataBuffer maxLength:sizeof(dataBuffer)]) {
            *errorStr = @"Could not read IPv4 address";
            return NO;
        }
        
        char ip[INET_ADDRSTRLEN];
        *host = [NSString stringWithCString:inet_ntop(AF_INET, dataBuffer, ip, sizeof(ip)) encoding:NSUTF8StringEncoding];
        [data appendBytes:dataBuffer length:sizeof dataBuffer];
        
//        NSLog(@"conn. Target host as IPv4 address: %@, data: %@", targetHost, fragmentData);
    }
    else if (0x03 == addressType) { // Domain name, 1 byte of name length followed by the name
//        NSLog(@"conn. Reading domain name...");
        uint8_t nameLength;
        if (1 != [inputStream read:&nameLength maxLength:1]) {
            *errorStr = @"Could not read domain name length";
            return NO;
        }
        uint8_t domainName[nameLength];
        if (sizeof(domainName) != [inputStream read:domainName maxLength:sizeof(domainName)]) {
            *errorStr = @"Could not read domain name";
            return NO;
        }
        *host = [[[NSString alloc] initWithBytes:domainName length:nameLength encoding:NSUTF8StringEncoding] autorelease];
        [data appendBytes:&nameLength length:1];
        [data appendBytes:domainName length:nameLength];
//        NSLog(@"conn. Target host as domain name: %@, data: %@", targetHost, fragmentData);
    }
    else if (0x04 == addressType) { // IPv6 address, 16 bytes
//        NSLog(@"conn. Reading IPv6 address...");
        uint8_t dataBuffer[16];
        if (sizeof dataBuffer != [inputStream read:dataBuffer maxLength:sizeof dataBuffer]) {
            *errorStr = @"Could not read IPv6 address";
            return NO;
        }
        char ip[INET6_ADDRSTRLEN];
        *host = [NSString stringWithCString:inet_ntop(AF_INET6, dataBuffer, ip, sizeof ip) encoding:NSUTF8StringEncoding];
        [data appendBytes:dataBuffer length:sizeof dataBuffer];
        
//        NSLog(@"conn. Target host as IPv6 address: %@, data: %@", targetHost, fragmentData);
    }
    
    // request's field 6: port number, 2 bytes
    uint8_t rawPort[2];
    if (2 != [inputStream read:rawPort maxLength:2]) {
        *errorStr = @"Could not read port number";
        return NO;
    }
    *port = (rawPort[0] << 8 | rawPort[1]);
        
    [data appendBytes:rawPort length:2];
    *fragmentData = data;
    
    return YES;
}

- (void)establishConnectionWithTarget {
//    NSLog(@"conn. Trying to establish TCP/IP connection with %@:%d...", targetHost, targetPort);
    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;
    CFStreamCreatePairWithSocketToHost(NULL, (CFStringRef)targetHost, targetPort, &readStream, &writeStream);
    
    if (!readStream || !writeStream) {
        NSLog(@"conn. Could not establish TCP/IP connection with %@:%d", targetHost, targetPort);
        [self invalidate];
        return;
    }
    
    targetInputStream = NSMakeCollectable(readStream);
    targetOutputStream = NSMakeCollectable(writeStream);
    [self setupInputStream:targetInputStream outputStream:targetOutputStream];
    
    OnThread([self validParentThread], NO, ^{
        [delegate TCPConnectionWithTargetHostEstablished:self];
    });
}

- (void)request {
    if (!isValid) {
        return;
    }
    
//    NSLog(@"conn. Getting request from client...");
    
    uint8_t headerFragment[3];
    if (sizeof headerFragment != [clientInputStream read:headerFragment maxLength:sizeof headerFragment]) {
        NSLog(@"conn. Could not read connection request header");
        [self invalidate];
        return;
    }
    
    // field 1: SOCKS version number
    if (0x05 != headerFragment[0]) {
        NSLog(@"conn. Wrong SOCKS version");
        [self invalidate];
        return;
    }
    
    // field 2: command code
    uint8_t commandCode = headerFragment[1];
//    NSLog(@"conn. Command code: %d", commandCode);
    
    // field 3: reserved, must be 0x00, just discarding without checking
    
    
    NSString *host = nil;
    NSUInteger port;
    NSMutableData *targetFragmentData;
    NSString *errorStr = nil;
    
    if (!getTargetInfoFromRequestFragment(self.clientInputStream, &host, &port, &targetFragmentData, &errorStr)) {
        NSLog(@"conn. %@", errorStr);
        [self invalidate];
        return;
    }
    
    
    if (0x01 == commandCode) { // establish a TCP/IP stream connection
        self.targetHost = host;
        self.targetPort = port;
        
        nextActionOnClientInput = NULL; // going to proxy mode
        [toClientData setData:[NSData dataWithBytes:"\x05\x00\x00" length:3]]; // Response header fragment. 0x00 - request granted
        [toClientData appendData:targetFragmentData];
//        NSLog(@"conn. Response to client: %@", toClientData);

        [self writeToStream:clientOutputStream fromBuffer:toClientData];
        
        [self establishConnectionWithTarget];
        
        return;
    }
    else if (0x02 == commandCode) { // establish a TCP/IP port binding
        // Command not supported
    }
    else if (0x03 == commandCode ) { // associate a UDP port
        // Command not supported
    }

    NSLog(@"conn. Command %d not supported...", commandCode);
    [toClientData setData:[NSData dataWithBytes:"\x05\x07\x00" length:3]]; // 0x07 - command not supported/protocol error. request denied
    [toClientData appendData:targetFragmentData];
    
    [self writeToStream:clientOutputStream fromBuffer:toClientData];
    [self invalidate];
}

- (void)dealloc {
    NSLog(@"conn. %@ destroyed", [self connectionStr]);
    
    [self invalidate];
    
    self.delegate = nil;
    
    self.clientHost = nil;
    self.targetHost = nil;
    self.clientInputStream = nil;
    self.clientOutputStream = nil;
    self.targetInputStream = nil;
    self.targetOutputStream = nil;
    
    self.toClientData = nil;
    self.toTargetData = nil;
    
    [super dealloc];
}

@end



@implementation SOCKSServer

@synthesize port, delegate;

- (id)initWithPort:(uint16_t)initPort {
    if (self = [super init]) {
        self.port = initPort;
        connections = [[NSMutableArray alloc] init];
    }
    
    return self;
}

- (void)handleNewConnectionFromHost:(NSString *)peerHost port:(uint16_t)peerPort inputStream:(NSInputStream *)inStream outputStream:(NSOutputStream *)outStream {
//    NSLog(@"srv. Opening conn...");
    OnThread(workerThread, NO, ^{
        SOCKSConnection *conn = [[[SOCKSConnection alloc] initWithClientHost:peerHost clientPort:peerPort inputStream:inStream outputStream:outStream] autorelease];
        conn.delegate = self;
        [conn start];
        [connections addObject:conn];
    });
}

static void SOCKSServerAcceptCallBack(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
    if (kCFSocketAcceptCallBack != type) {
        return;
    }

    CFSocketNativeHandle nativeSocketHandle = *(CFSocketNativeHandle *)data;
    struct sockaddr_storage addr; 
    NSString *host;
    NSUInteger port = NSUIntegerMax;
    socklen_t addrLen = sizeof addr; 
    if (0 == getpeername(nativeSocketHandle, (struct sockaddr*)&addr, &addrLen)) {
        if (addr.ss_family == AF_INET) {
            struct sockaddr_in *s = (struct sockaddr_in *)&addr; 
            port = ntohs(s->sin_port); 
            char ip[INET_ADDRSTRLEN];
            host = [NSString stringWithCString:inet_ntop(AF_INET, &s->sin_addr, ip, sizeof ip) encoding:NSUTF8StringEncoding];
        } 
        else { // AF_INET6 
            struct sockaddr_in6 *s = (struct sockaddr_in6 *)&addr; 
            port = ntohs(s->sin6_port); // XXX?
            char ip[INET6_ADDRSTRLEN];
            host = [NSString stringWithCString:inet_ntop(AF_INET6, &s->sin6_addr, ip, sizeof ip) encoding:NSUTF8StringEncoding];
        }   
    }
    // deal with both IPv4 and IPv6: 
//    NSLog(@"srv. Client: %@:%d", host, port); 
    
    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;
    CFStreamCreatePairWithSocket(kCFAllocatorDefault, nativeSocketHandle, &readStream, &writeStream);

    if (readStream && writeStream) {
        CFReadStreamSetProperty(readStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
        CFWriteStreamSetProperty(writeStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
        SOCKSServer *server = (SOCKSServer *)info;
        [server handleNewConnectionFromHost:host port:port inputStream:(NSInputStream *)readStream outputStream:(NSOutputStream *)writeStream];
    }
    else {
        close(nativeSocketHandle);
    }
    
    if (readStream) {
        CFRelease(readStream);
    }
    if (writeStream) {
        CFRelease(writeStream);
    }
}

- (void)invalidate {
    if (NULL != ipv4Socket) {
        CFSocketInvalidate(ipv4Socket);
        CFRelease(ipv4Socket);
        ipv4Socket = NULL;
    }
    if (NULL != ipv6Socket) {
        CFSocketInvalidate(ipv6Socket);
        CFRelease(ipv6Socket);
        ipv6Socket = NULL;
    }
}

- (void)connectionDidBecomeInvalid:(SOCKSConnection *)conn {
    
}

- (void)connectionDidClose:(SOCKSConnection *)conn {
    OnThread(([self isRunning] ? workerThread : [self validParentThread]), NO, ^{
//        NSLog(@"srv. Removing connection: %@", conn);
        [connections removeObject:conn];
        // TODO: notify main thread on conn did close
    });
}

- (void)TCPConnectionWithTargetHostEstablished:(SOCKSConnection *)conn {
    
}


- (void)initialize {
    CFSocketContext ctx = {
        0, self, NULL, NULL, NULL
    };
    
    if (NULL == (ipv4Socket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, (CFSocketCallBack)&SOCKSServerAcceptCallBack, &ctx))) {
        NSLog(@"srv. Could not create IPv4 socket: %s", strerror(errno));
    }
    else {
        int yes = 1;
        setsockopt(CFSocketGetNative(ipv4Socket), SOL_SOCKET, SO_REUSEADDR, (void *)&yes, sizeof(yes));
        // if port is 0 for IPv4, kernel chooses it for us
        struct sockaddr_in addr4;
        memset(&addr4, 0, sizeof(addr4));
        addr4.sin_len = sizeof(addr4);
        addr4.sin_family = AF_INET;
        addr4.sin_port = htons(port);
        addr4.sin_addr.s_addr = htonl(INADDR_ANY);
        NSData *address4 = [NSData dataWithBytes:&addr4 length:sizeof(addr4)];
        if (kCFSocketSuccess != CFSocketSetAddress(ipv4Socket, (CFDataRef)address4)) {
            CFRelease(ipv4Socket);
            ipv4Socket = NULL;
            NSLog(@"srv. Could not bind to IPv4 address: %s", strerror(errno));
        }
        else {
            if (0 == port) {
                NSData *addr = [(NSData *)CFSocketCopyAddress(ipv4Socket) autorelease];
                memcpy(&addr4, [addr bytes], [addr length]);
                port = ntohs(addr4.sin_port);
            }
            CFRunLoopSourceRef source4 = CFSocketCreateRunLoopSource(kCFAllocatorDefault, ipv4Socket, 0);
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source4, kCFRunLoopCommonModes);
            CFRelease(source4);
        }
    }
    
    if (NULL == (ipv6Socket = CFSocketCreate(kCFAllocatorDefault, PF_INET6, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, (CFSocketCallBack)&SOCKSServerAcceptCallBack, &ctx))) {
        NSLog(@"srv. Could not create IPv6 socket: %s", strerror(errno));
    }
    else {
        int yes = 1;
        setsockopt(CFSocketGetNative(ipv6Socket), SOL_SOCKET, SO_REUSEADDR, (void *)&yes, sizeof(yes));
        
        struct sockaddr_in6 addr6;
        memset(&addr6, 0, sizeof(addr6));
        addr6.sin6_len = sizeof(addr6);
        addr6.sin6_family = AF_INET6;
        addr6.sin6_port = htons(port);
        memcpy(&(addr6.sin6_addr), &in6addr_any, sizeof(addr6.sin6_addr));
        NSData *address6 = [NSData dataWithBytes:&addr6 length:sizeof(addr6)];
        
        if (kCFSocketSuccess != CFSocketSetAddress(ipv6Socket, (CFDataRef)address6)) {
            CFRelease(ipv6Socket);
            ipv6Socket = NULL;
            NSLog(@"srv. Could not bind to IPv6 address: %s", strerror(errno));
        }
        else {
            CFRunLoopSourceRef source6 = CFSocketCreateRunLoopSource(kCFAllocatorDefault, ipv6Socket, 0);
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source6, kCFRunLoopCommonModes);
            CFRelease(source6);
        }
    }
    
    if (NULL == ipv4Socket && NULL == ipv6Socket) {
        shouldStop = YES;
        OnThread([self validParentThread], NO, ^{
            [delegate SOCKSServerCouldNotStart:self withError:@"no sockets available"];
        });
        return;
    }
    
    
    OnThread([self validParentThread], NO, ^{
        [delegate SOCKSServerDidStart:self];
    });
}

- (void)loop {
//    NSLog(@"srv. shouldStop: %d", shouldStop);
}

- (void)cleanup {
    [self invalidate];
//    NSLog(@"srv. in cleanup");
    OnThread([self validParentThread], NO, ^{
//        NSLog(@"srv. about to call delegate");
        [delegate SOCKSServerDidStop:self];
    });
}

- (void)dealloc {
    [self invalidate];
    
    [connections release];

    self.delegate = nil;
    
    [super dealloc];
}

@end
