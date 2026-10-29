// AdVanish contributions: Copyright (C) 2026 maxblox2999.
// GPL-3.0-only with origin terms; see LICENSE and NOTICE.md.

#pragma once
#import <Foundation/Foundation.h>
#ifdef ADSPEED_ROOTHIDE
#import <roothide.h>
#endif

static inline NSArray<NSString *> *ASPPrefsPaths(NSString *domain) {
    NSString *path = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", domain];
#ifdef ADSPEED_ROOTHIDE
    return @[jbroot(path)];
#else
    return @[[@"/var/jb" stringByAppendingString:path], path];
#endif
}

static inline NSString *ASPPrefsWritePath(NSString *domain) {
    NSArray<NSString *> *paths = ASPPrefsPaths(domain);
#ifdef ADSPEED_ROOTHIDE
    return paths.firstObject;
#else
    return [NSFileManager.defaultManager fileExistsAtPath:@"/var/jb"] ? paths.firstObject : paths.lastObject;
#endif
}
