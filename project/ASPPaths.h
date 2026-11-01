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

static inline NSDictionary *ASPReadPreferencesAtPaths(NSArray<NSString *> *paths) {
    NSMutableDictionary *values = NSMutableDictionary.dictionary;
    for (NSString *path in paths.reverseObjectEnumerator) {
        NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:path];
        if (saved) [values addEntriesFromDictionary:saved];
    }
    return values;
}

static inline NSMutableDictionary *ASPApplicationPreferences(NSDictionary *stored, NSString *bundle) {
    NSMutableDictionary *values = NSMutableDictionary.dictionary;
    values[@"Enabled"] = stored[@"Enabled"] ?: @YES;
    NSString *prefix = [bundle stringByAppendingString:@"-"];
    for (id key in stored) {
        if ([key isKindOfClass:NSString.class] && [key hasPrefix:prefix]) {
            values[[key substringFromIndex:prefix.length]] = stored[key];
        }
    }
    values[@"AppEnabled"] = stored[[@"enabled-" stringByAppendingString:bundle]] ?: @NO;
    return values;
}
static inline BOOL ASPPreferenceFlag(NSDictionary *values, NSString *key, BOOL fallback) {
    id raw = values[key];
    return [raw respondsToSelector:@selector(boolValue)] ? [raw boolValue] : fallback;
}
static inline BOOL ASPAutomaticAdsEnabled(NSDictionary *values) {
    return ASPPreferenceFlag(values, @"AutomaticAds", !ASPPreferenceFlag(values, @"ManualSkip", NO));
}
