//
//  NSDictionaryAdditions.h
//  Tabi_Mac_OS_X
//
//  Created by Vyacheslav Zakovyrya on 2/21/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface NSDictionary(TabiAdditions) 

- (BOOL)canConnect;

- (NSString *)hostNameWithoutLocalSuffix;

@end

