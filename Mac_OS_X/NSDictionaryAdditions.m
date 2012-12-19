//
//  NSDictionaryAdditions.m
//  Tabi_Mac_OS_X
//
//  Created by Vyacheslav Zakovyrya on 2/21/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "NSDictionaryAdditions.h"


@implementation NSDictionary(TabiAdditions)

- (BOOL)canConnect {
    return nil != [self valueForKey:@"serverAddressToConnectTo"] && nil != [self valueForKey:@"localNetworkInterfaceIDToConnectFrom"];
}

- (NSString *)hostNameWithoutLocalSuffix {
    return [[self valueForKey:@"hostName"] hostNameWithoutLocalSuffix];
}

@end
