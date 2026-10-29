// Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.
#pragma once
#import <Foundation/Foundation.h>
#ifdef ADSPEED_ROOTHIDE
#import <roothide.h>
#endif

static inline NSArray<NSString *> *ASPPrefsPaths(NSString *domain) {
    NSString *path = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", domain];
#ifdef ADSPEED_ROOTHIDE
    return @[jbroot(path)];
#elif defined(ADSPEED_ROOTLESS)
    return @[[@"/var/jb" stringByAppendingString:path], path];
#else
    return @[path];
#endif
}

static inline NSString *ASPPrefsWritePath(NSString *domain) {
    return ASPPrefsPaths(domain).firstObject;
}
