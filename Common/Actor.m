#import "Actor.h"
#import "BlocksAdditions.h"

@implementation Actor

@synthesize workerThread, launchThread;

- (NSThread *)validParentThread {
    return [launchThread isExecuting] ? launchThread : [NSThread mainThread];
}

- (NSDate *)dateToRunBefore {
    return [NSDate distantFuture];
}

- (BOOL)isRunning {
    return [workerThread isExecuting];
}

- (void)initialize {
    
}

- (void)cleanup {
    
}

- (void)loop {
    
}

- (void)run {
    shouldStop = NO;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    [self initialize];
    
    @try {
        do {
            [self loop];
            [pool release];            
            pool = [[NSAutoreleasePool alloc] init];
        } while (!shouldStop && [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[self dateToRunBefore]]);
    }
    @catch (NSException *e) {
        NSLog(@"actor. Exception caught: %@", [e reason]);
    }
    @finally {
        [self cleanup];
        if (!pool) {
            pool = [[NSAutoreleasePool alloc] init];
        }
        [pool release];
    }
    
}

- (void)start {
    self.launchThread = [NSThread currentThread];
    self.workerThread = [[[NSThread alloc] initWithTarget:self selector:@selector(run) object:nil] autorelease];
    [workerThread start];
}

- (void)stop {
    OnThread(workerThread, NO, ^{
        shouldStop = YES;
    });
}

- (void)dealloc {
    self.launchThread = nil;
    self.workerThread = nil;
    
    [super dealloc];
}

@end
