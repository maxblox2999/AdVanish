// Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.
#pragma once
#import <Foundation/Foundation.h>

static inline BOOL ASPApplicationHost(NSString *identifier, NSString *path) {
    return identifier.length && ![identifier hasPrefix:@"com.apple."] &&
        [path.pathExtension.lowercaseString isEqualToString:@"app"];
}

static inline BOOL ASPAppStoreURL(NSURL *url) {
    NSString *scheme = url.scheme.lowercaseString;
    if ([@[@"itms", @"itmss", @"itms-apps", @"itms-appss", @"itms-services"] containsObject:scheme]) return YES;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) return NO;
    NSString *host = url.host.lowercaseString;
    if ([host hasSuffix:@"."]) host = [host substringToIndex:host.length - 1];
    return [host isEqualToString:@"apps.apple.com"] || [host isEqualToString:@"itunes.apple.com"];
}
