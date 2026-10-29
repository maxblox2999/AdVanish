// AdVanish contributions: Copyright (C) 2026 maxblox2999.
// GPL-3.0-only with origin terms; see LICENSE and NOTICE.md.

#import "ASPListBase.h"
#import "../ASPPaths.h"
#import <UIKit/UIKit.h>

static NSString *const kDomain = @"com.34306-sr.adspeed";
static NSString *const kNotify = @"com.34306-sr.adspeed/reloadPrefs";

@implementation ASPListBase

+ (NSString *)prefsPathForDomain:(NSString *)domain {
    return ASPPrefsWritePath(domain);
}

- (NSString *)pathForSpecifier:(PSSpecifier *)specifier {
    return [ASPListBase prefsPathForDomain:[specifier propertyForKey:@"defaults"] ?: kDomain];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:[self pathForSpecifier:specifier]];
    id value = settings[[specifier propertyForKey:@"key"]];
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *path = [self pathForSpecifier:specifier];
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
    settings[[specifier propertyForKey:@"key"]] = value;
    [settings writeToFile:path atomically:YES];

    NSString *notification = [specifier propertyForKey:@"PostNotification"];
    if (notification) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             (__bridge CFStringRef)notification, NULL, NULL, YES);
    }
}

- (BOOL)boolPref:(NSString *)key default:(BOOL)def {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:[ASPListBase prefsPathForDomain:kDomain]];
    id v = d[key];
    return v ? [v boolValue] : def;
}

// Direct key write (used by the swipe-to-toggle quick action), matching the path/domain
// and reload notification used by the specifier setter.
- (void)setBool:(BOOL)value forKey:(NSString *)key {
    NSString *path = [ASPListBase prefsPathForDomain:kDomain];
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
    settings[key] = @(value);
    [settings writeToFile:path atomically:YES];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kNotify, NULL, NULL, YES);
}

- (PSSpecifier *)switchSpecifierNamed:(NSString *)name key:(NSString *)key default:(BOOL)def {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:name
                                                   target:self
                                                      set:@selector(setPreferenceValue:specifier:)
                                                      get:@selector(readPreferenceValue:)
                                                   detail:nil
                                                     cell:PSSwitchCell
                                                     edit:nil];
    [s setProperty:kDomain forKey:@"defaults"];
    [s setProperty:kNotify forKey:@"PostNotification"];
    [s setProperty:key forKey:@"key"];
    [s setProperty:@(def) forKey:@"default"];
    return s;
}

// A switch shown as an indented sub-item of the row above it.
- (PSSpecifier *)subSwitchNamed:(NSString *)name key:(NSString *)key default:(BOOL)def {
    PSSpecifier *s = [self switchSpecifierNamed:[@"      " stringByAppendingString:name] key:key default:def];
    [s setProperty:@1 forKey:@"indentationLevel"];
    return s;
}

- (PSSpecifier *)groupNamed:(NSString *)name footer:(NSString *)footer {
    PSSpecifier *g = [PSSpecifier groupSpecifierWithName:name];
    if (footer) [g setProperty:footer forKey:@"footerText"];
    return g;
}

@end
