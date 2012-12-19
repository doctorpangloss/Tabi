//
//  EventNotifyingWindow.h
//  Tabi_iPhone
//
//  Created by Vyacheslav Zakovyrya on 2/18/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol UIWindowEventDelegate

- (void)eventHappened:(UIEvent *)event;

@end


@interface EventNotifyingUIWindow : UIWindow {
    id<UIWindowEventDelegate>eventDelegate;
}

@property(nonatomic, retain) id<UIWindowEventDelegate>eventDelegate;

@end
