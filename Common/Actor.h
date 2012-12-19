#import <Foundation/Foundation.h>


@interface Actor : NSObject {
    NSThread *workerThread, *launchThread;
    BOOL shouldStop;
}

@property (nonatomic, retain) NSThread *workerThread, *launchThread;

- (NSThread *)validParentThread;

- (NSDate *)dateToRunBefore;
- (void)start;
- (void)stop;
- (BOOL)isRunning;


@end

