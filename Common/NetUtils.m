//
//  NetUtils.m
//  Tabi
//
//  Created by Vyacheslav Zakovyrya on 1/22/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "NetUtils.h"
#import <arpa/inet.h>
#import <ifaddrs.h>

void* InAddrStruct(struct sockaddr *sa) {
    if (AF_INET == sa->sa_family) {
        return &(((struct sockaddr_in*)sa)->sin_addr);
    }
    return &(((struct sockaddr_in6*)sa)->sin6_addr);
}

NSString* AddressString(struct sockaddr *sa) {
    void *if_in_addr = InAddrStruct(sa);
    char if_addr_buff[(sa->sa_family == AF_INET ? INET_ADDRSTRLEN : INET6_ADDRSTRLEN)];
    memset(if_addr_buff, 0, sizeof if_addr_buff);
    inet_ntop(sa->sa_family, if_in_addr, if_addr_buff, sizeof if_addr_buff);
    NSString *addressStr = [NSString stringWithCString:if_addr_buff encoding:NSUTF8StringEncoding];
    
    return addressStr;
}

BOOL processInetPTONStatus(NSUInteger status, NSString *addressStr) {
    if (0 == status) {
        NSLog(@"Address %@ is messed up", addressStr);
        return NO;
    }
    else if (-1 == status) {
        NSLog(@"Could not PTON address %@: %s", addressStr, strerror(errno));
        return NO;
    }
    
    return YES;
}

NSString* NetworkOfIPv4Address(NSString *addressStr, NSString *maskStr) {
    struct sockaddr_in addr;
    struct sockaddr_in mask;
    if (!processInetPTONStatus(inet_pton(AF_INET, [addressStr cStringUsingEncoding:NSUTF8StringEncoding], &(addr.sin_addr)), addressStr)) {
        return nil;
    }
    if (!processInetPTONStatus(inet_pton(AF_INET, [maskStr cStringUsingEncoding:NSUTF8StringEncoding], &(mask.sin_addr)), maskStr)) {
        return nil;
    }
    
    struct sockaddr_in masked_addr;
    memset(&masked_addr, 0, sizeof masked_addr);
    
    masked_addr.sin_family = AF_INET;
    masked_addr.sin_len = sizeof masked_addr;
    
    uint8_t addr_buff[sizeof addr.sin_addr.s_addr];
    memcpy(addr_buff, &(addr.sin_addr.s_addr), sizeof addr_buff);
    uint8_t mask_buff[sizeof addr_buff];
    memcpy(mask_buff, &(mask.sin_addr.s_addr), sizeof mask_buff);
    
    uint8_t masked_addr_buff[sizeof addr_buff];
    for (int i = 0; i < sizeof masked_addr_buff; i++) {
        masked_addr_buff[i] = addr_buff[i] & mask_buff[i];
    }
    memcpy(&(masked_addr.sin_addr.s_addr), masked_addr_buff, sizeof masked_addr_buff);
    memset(masked_addr.sin_zero, 0, sizeof masked_addr.sin_zero);
    
    return AddressString((struct sockaddr *)&masked_addr);
}

NSArray* NetworkInterfaces() {
    struct ifaddrs *if_addrs;
    int status = getifaddrs(&if_addrs);
    if (0 != status) {
        NSLog(@"Could not get network interfaces: %s", strerror(errno));
        return nil;
    }
    
    NSMutableArray *interfaces = [NSMutableArray array];
    
    for (struct ifaddrs *if_addrs_cursor = if_addrs; NULL != if_addrs_cursor; if_addrs_cursor = if_addrs_cursor->ifa_next) {
        NSString *name = [NSString stringWithCString:if_addrs_cursor->ifa_name encoding:NSUTF8StringEncoding];
        NSMutableDictionary *interfaceDict = [NSMutableDictionary dictionaryWithObject:name forKey:@"name"];
        if (NULL != if_addrs_cursor->ifa_addr) {
            struct sockaddr *if_addr = if_addrs_cursor->ifa_addr;
            NSString *addressStr = AddressString(if_addr);
            [interfaceDict setValue:addressStr forKey:@"address"];
            
            NSString *addressFamily = nil;
            if (AF_INET == if_addrs_cursor->ifa_addr->sa_family) {
                addressFamily = tIPv4;
            }
            else if (AF_INET6 == if_addrs_cursor->ifa_addr->sa_family) {
                addressFamily = tIPv6;
            }
            
            [interfaceDict setValue:addressFamily forKey:@"addressFamily"];
            
            if (NULL != if_addrs_cursor->ifa_dstaddr) {
                NSString *broadcastAddressStr = AddressString(if_addrs_cursor->ifa_dstaddr);
                [interfaceDict setValue:broadcastAddressStr forKey:@"broadcastAddress"];
            }
            
            if (NULL != if_addrs_cursor->ifa_netmask) {
                NSString *netMaskStr = AddressString(if_addrs_cursor->ifa_netmask);
                [interfaceDict setValue:netMaskStr forKey:@"netMask"];
            }
            
        }
        [interfaces addObject:interfaceDict];
    }
    
    freeifaddrs(if_addrs);
    
    return interfaces;
}

