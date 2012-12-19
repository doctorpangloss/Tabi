// Contains code created by Michael Ash
// http://www.mikeash.com/pyblog/friday-qa-2009-08-14-practical-blocks.html

#import "BlocksAdditions.h"

@interface NSObject (BlockAdditions)

- (void)my_callBlock;
- (void)my_callBlockWithObject:(id)obj;

@end


@implementation NSObject (BlockAdditions)

- (void)my_callBlock {
    void (^block)() = (id)self;
    block();
}

- (void)my_callBlockWithObject:(id)obj {
    void (^block)(id obj) = (id)self;
    block(obj);
}

@end


void InBackground(BasicBlock block) {
    [NSThread detachNewThreadSelector:@selector(my_callBlock) toTarget:[[block copy] autorelease] withObject:nil];
}
void OnMainThread(BOOL shouldWait, BasicBlock block) {
    [[[block copy] autorelease] performSelectorOnMainThread:@selector(my_callBlock) withObject:nil waitUntilDone:shouldWait];
}
void OnThread(NSThread *thread, BOOL shouldWait, BasicBlock block) {
    [[[block copy] autorelease] performSelector:@selector(my_callBlock) onThread:thread withObject:nil waitUntilDone:shouldWait];
}
void AfterDelay(NSTimeInterval delay, BasicBlock block) {
    [[[block copy] autorelease] performSelector:@selector(my_callBlock) withObject:nil afterDelay:delay];
}
void WithAutoreleasePool(BasicBlock block) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    block();
    [pool release];
}
void Parallelized(int count, void (^block)(int i)) {
    for (int i = 0; i < count; i++) {
        InBackground(^{
            block(i);
        });
    }
}


@implementation NSLock (BlocksAdditions)

- (void)whileLocked:(BasicBlock)block {
    [self lock];
    @try {
        block();
    }
    @finally {
        [self unlock];
    }
}

@end


@implementation NSNotificationCenter (BlocksAdditions)

- (void)addObserverBlock:(void (^)(NSNotification *))block forName:(NSString *)name {
    [self addObserver:[block copy] selector:@selector(my_callBlock) name:name object:nil];
}

@end


@interface DownloadDelegate : NSObject {
    ResultBlock beginBlock;
    ResultBlock dataReceivedBlock;
    BasicBlock successBlock;
    ErrorBlock errorBlock;
    BasicBlock completeBlock;
    
    ErrorBlock processErrorBlock;
    
    NSInteger statusCode;
} 

@property (nonatomic, retain) ResultBlock beginBlock;
@property (nonatomic, retain) ResultBlock dataReceivedBlock;
@property (nonatomic, retain) BasicBlock successBlock;
@property (nonatomic, retain) ErrorBlock errorBlock;
@property (nonatomic, retain) BasicBlock completeBlock;

@property (nonatomic, retain) ErrorBlock processErrorBlock;

- (id)initWithOnBeginDo:(ResultBlock)onBeginBlock onDataReceivedDo:(ResultBlock)onDataReceivedBlock onSuccessDo:(BasicBlock)onSuccessBlock onErrorDo:(ErrorBlock)onErrorBlock onCompleteDo:(BasicBlock)onCompleteBlock;

@end

@implementation DownloadDelegate

@synthesize beginBlock, dataReceivedBlock, successBlock, errorBlock, completeBlock;
@synthesize processErrorBlock;

- (id)initWithOnBeginDo:(ResultBlock)onBeginBlock onDataReceivedDo:(ResultBlock)onDataReceivedBlock onSuccessDo:(BasicBlock)onSuccessBlock onErrorDo:(ErrorBlock)onErrorBlock onCompleteDo:(BasicBlock)onCompleteBlock {
    if (self = [super init]) {
        self.beginBlock = [[onBeginBlock copy] autorelease];
        self.dataReceivedBlock = [[onDataReceivedBlock copy] autorelease];
        self.successBlock = [[onSuccessBlock copy] autorelease];
        self.errorBlock = [[onErrorBlock copy] autorelease];
        self.completeBlock = [[onCompleteBlock copy] autorelease];
        
        self.processErrorBlock = [[^(NSString *err) {
            self.errorBlock(err);
            self.completeBlock();
        } copy] autorelease];
    }
    
    return self;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    NSHTTPURLResponse *httpRes = (NSHTTPURLResponse *)response;
    statusCode = [httpRes statusCode];
//    NSLog(@"status code: %d", statusCode);
    if (statusCode >= 200 && statusCode < 300) {
        self.beginBlock(httpRes);
        return;
    }
    
    self.processErrorBlock([NSHTTPURLResponse localizedStringForStatusCode:statusCode]);
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    self.dataReceivedBlock(data);
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    if (statusCode >= 200 && statusCode < 300) {
        self.successBlock();
    }
    self.completeBlock();
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    self.processErrorBlock([error localizedDescription]);
}

- (void)dealloc {
    self.beginBlock = nil;
    self.dataReceivedBlock = nil;
    self.successBlock = nil;
    self.errorBlock = nil;
    self.completeBlock = nil;
    
    self.processErrorBlock = nil;
    
    [super dealloc];
}

@end


@implementation NSURLConnection (BlocksAdditions)

+ (void)sendAsynchronousRequest:(NSURLRequest *)request onCompletionDo:(void (^)(NSData *data, NSURLResponse *response, NSError *err))block {
    NSThread *originalThread = [NSThread currentThread];
    InBackground(^{
        WithAutoreleasePool(^{
            NSURLResponse *response = nil;
            NSError *error;
            NSData *data = [self sendSynchronousRequest:request returningResponse:&response error:&error];
            OnThread(originalThread, NO, ^{
                block(data, response, error);
            });
        });
    });
}

+ (NSURLConnection *)sendAsynchronousRequest:(NSURLRequest *)request onBeginDo:(ResultBlock)beginBlock onDataReceivedDo:(ResultBlock)dataReceivedBlock onSuccessDo:(ResultBlock)successBlock onErrorDo:(ErrorBlock)errorBlock onCompleteDo:(BasicBlock)completeBlock {
    NSURLConnection *connection = nil;
 
    __block NSHTTPURLResponse *response = nil;
    
    connection = [NSURLConnection connectionWithRequest:request delegate:[[[DownloadDelegate alloc] initWithOnBeginDo:^(id res) {
        response = res;
        beginBlock(res);
    } onDataReceivedDo:dataReceivedBlock onSuccessDo:^{
        successBlock(response);
    } onErrorDo:errorBlock onCompleteDo:^{
        completeBlock();
    }] autorelease]];
    
    [connection start];
    
    return connection;
}

+ (NSURLConnection *)asynchronouslyDownloadFileFromRequest:(NSURLRequest *)request toDirPath:(NSString *)targetDirPath onBeginDo:(ResultBlock)beginBlock onDataReceivedDo:(ResultBlock)dataReceivedBlock onSuccessDo:(ResultBlock)successBlock onErrorDo:(ErrorBlock)errorBlock onCompleteDo:(BasicBlock)completeBlock {
    __block NSURLConnection *connection = nil;
    __block NSString *filePath = nil;
    __block NSFileHandle *fh = nil;
    
    connection = [NSURLConnection connectionWithRequest:request delegate:[[[DownloadDelegate alloc] initWithOnBeginDo:^(id res) {
        filePath = [[targetDirPath stringByAppendingFormat:@"/%@", [res suggestedFilename], nil] retain];
        if (![[NSFileManager defaultManager] createFileAtPath:filePath contents:[NSData data] attributes:nil]) {
            errorBlock([NSString stringWithFormat:@"could not create file at path %@", filePath]);
            [connection cancel];
            completeBlock();
            return;
        }
//        NSLog(@"saving to: %@", filePath);
        fh = [[NSFileHandle fileHandleForWritingAtPath:filePath] retain];
        beginBlock(res);
    } onDataReceivedDo:^(id data) {
        if (nil == fh) {
            // TODO: error
            return;
        }
        [fh writeData:data];
//        NSLog(@"data written");
        dataReceivedBlock(data);
    } onSuccessDo:^{
//        NSLog(@"success");
        
        // How the hell this could be nil at this point?
        if (nil != fh) {
            [fh closeFile];
            [fh release];
            fh = nil;
        }
        successBlock(filePath);
    } onErrorDo:^(NSString *err) {
        errorBlock(err);
    } onCompleteDo:^{
//        NSLog(@"cleaning up...");
        if (nil != fh) {
            [fh closeFile];
            [fh release];
        }
        [filePath release];
        completeBlock();
//        NSLog(@"done cleaning up...");
    }] autorelease]];
    
    [connection start];
    
    return connection;
}

@end
