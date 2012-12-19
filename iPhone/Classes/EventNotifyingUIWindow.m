//
//  EventNotifyingWindow.m
//  Tabi_iPhone
//
//  Created by Vyacheslav Zakovyrya on 2/18/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "EventNotifyingUIWindow.h"


@implementation EventNotifyingUIWindow

@synthesize eventDelegate;

- (void)sendEvent:(UIEvent *)event {
    [eventDelegate eventHappened:event];
    [super sendEvent:event];
}

- (void)dealloc {
    self.eventDelegate = nil;
    
    [super dealloc];
}

@end
