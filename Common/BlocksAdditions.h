// Contains code created by Michael Ash
// http://www.mikeash.com/pyblog/friday-qa-2009-08-14-practical-blocks.html

#import <Foundation/Foundation.h>

typedef void (^BasicBlock)(void);
typedef void (^SuccessBlock)(id);
typedef void (^ResultBlock)(id);
typedef void (^ErrorBlock)(NSString *);


void InBackground(BasicBlock block);
void OnMainThread(BOOL shouldWait, BasicBlock block);
void OnThread(NSThread *thread, BOOL shouldWait, BasicBlock block);
void AfterDelay(NSTimeInterval delay, BasicBlock block);
void WithAutoreleasePool(BasicBlock block);
void Parallelized(int count, void (^block)(int i));

@interface NSLock (BlocksAdditions)

- (void)whileLocked:(BasicBlock)block;

@end

@interface NSNotificationCenter (BlocksAdditions)

- (void)addObserverBlock:(void (^)(NSNotification *note))block forName:(NSString *)name;

@end

@interface NSURLConnection (BlocksAdditions)

+ (void)sendAsynchronousRequest:(NSURLRequest *)request onCompletionDo:(void(^)(NSData *data, NSURLResponse *response, NSError *error))block;

+ (NSURLConnection *)sendAsynchronousRequest:(NSURLRequest *)request onBeginDo:(ResultBlock)beginBlock onDataReceivedDo:(ResultBlock)dataReceivedBlock onSuccessDo:(ResultBlock)successBlock onErrorDo:(ErrorBlock)errorBlock onCompleteDo:(BasicBlock)completeBlock;

+ (NSURLConnection *)asynchronouslyDownloadFileFromRequest:(NSURLRequest *)request toDirPath:(NSString *)targetDirPath onBeginDo:(ResultBlock)beginBlock onDataReceivedDo:(ResultBlock)dataReceivedBlock onSuccessDo:(ResultBlock)successBlock onErrorDo:(ErrorBlock)errorBlock onCompleteDo:(BasicBlock)completeBlock;

@end

