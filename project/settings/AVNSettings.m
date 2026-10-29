// Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.

#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <objc/message.h>
#import "../ASPPaths.h"

@interface AVNSettingsController : PSListController
@property (nonatomic, strong) NSMutableDictionary *cachedValues;
@end

@implementation AVNSettingsController
- (NSMutableDictionary *)database {
    if (!self.cachedValues) {
        NSDictionary *loaded = [NSDictionary dictionaryWithContentsOfFile:ASPPrefsWritePath(@"com.34306-sr.adspeed")];
        self.cachedValues = loaded ? loaded.mutableCopy : NSMutableDictionary.dictionary;
    }
    return self.cachedValues;
}
- (NSString *)application {
    return [self.specifier propertyForKey:@"AVNApplication"];
}
- (NSString *)storageKey:(NSString *)feature {
    NSString *application = self.application;
    if (!application.length) return feature;
    if ([feature isEqualToString:@"Enabled"]) return [@"enabled-" stringByAppendingString:application];
    return [NSString stringWithFormat:@"%@-%@", application, feature];
}
- (id)valueForControl:(PSSpecifier *)control {
    id saved = self.database[[control propertyForKey:@"AVNKey"]];
    return saved ?: [control propertyForKey:@"default"];
}
- (void)changeValue:(id)value forControl:(PSSpecifier *)control {
    NSMutableDictionary *database = self.database.mutableCopy;
    NSString *key = [control propertyForKey:@"AVNKey"];
    if ([key isEqualToString:[self storageKey:@"ManualSkip"]]) {
        NSString *automatic = [self storageKey:@"AutomaticAds"];
        if (!database[automatic]) database[automatic] = @(![database[key] boolValue]);
    }
    database[key] = value;
    NSString *file = ASPPrefsWritePath(@"com.34306-sr.adspeed");
    [NSFileManager.defaultManager createDirectoryAtPath:file.stringByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:nil error:nil];
    if (![database writeToFile:file atomically:YES]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"AdVanish" message:@"Could not save settings." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        self.cachedValues = database;
    }
    _specifiers = nil;
    [self reloadSpecifiers];
}
- (PSSpecifier *)section:(NSString *)title note:(NSString *)note {
    PSSpecifier *section = [PSSpecifier groupSpecifierWithName:title];
    if (note) [section setProperty:note forKey:@"footerText"];
    return section;
}
- (PSSpecifier *)toggle:(NSString *)title feature:(NSString *)feature initial:(BOOL)initial {
    PSSpecifier *control = [PSSpecifier preferenceSpecifierNamed:title target:self
        set:@selector(changeValue:forControl:) get:@selector(valueForControl:)
        detail:Nil cell:PSSwitchCell edit:Nil];
    [control setProperty:[self storageKey:feature] forKey:@"AVNKey"];
    [control setProperty:@(initial) forKey:@"default"];
    return control;
}
- (NSArray<NSDictionary *> *)applications {
    Class registry = NSClassFromString(@"LSApplicationWorkspace");
    SEL singleton = NSSelectorFromString(@"defaultWorkspace");
    SEL listing = NSSelectorFromString(@"allApplications");
    if (![registry respondsToSelector:singleton]) return @[];
    id workspace = ((id (*)(id, SEL))objc_msgSend)(registry, singleton);
    if (![workspace respondsToSelector:listing]) return @[];
    id collection = ((id (*)(id, SEL))objc_msgSend)(workspace, listing);
    if (![collection isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *result = NSMutableArray.array;
    for (id proxy in collection) {
        NSMutableDictionary *values = NSMutableDictionary.dictionary;
        for (NSString *property in @[@"applicationType", @"applicationIdentifier", @"localizedName"]) {
            SEL selector = NSSelectorFromString(property);
            if ([proxy respondsToSelector:selector]) {
                id value = ((id (*)(id, SEL))objc_msgSend)(proxy, selector);
                if ([value isKindOfClass:NSString.class]) values[property] = value;
            }
        }
        NSString *identifier = values[@"applicationIdentifier"];
        if (![values[@"applicationType"] isEqual:@"User"] || !identifier.length) continue;
        [result addObject:@{@"identifier": identifier, @"title": values[@"localizedName"] ?: identifier}];
    }
    return [result sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [left[@"title"] localizedCaseInsensitiveCompare:right[@"title"]];
    }];
}
- (void)viewWillAppear:(BOOL)animated {
    self.cachedValues = nil;
    _specifiers = nil;
    [super viewWillAppear:animated];
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *rows = NSMutableArray.array;
    if (!self.application.length) {
        self.title = @"AdVanish";
        [rows addObject:[self section:nil note:@"maxblox2999"]];
        [rows addObject:[self toggle:@"Enabled" feature:@"Enabled" initial:YES]];
        [rows addObject:[self section:@"Apps" note:@"Changes apply after reopening the app."]];
        for (NSDictionary *app in self.applications) {
            PSSpecifier *link = [PSSpecifier preferenceSpecifierNamed:app[@"title"] target:nil set:NULL get:NULL
                detail:AVNSettingsController.class cell:PSLinkCell edit:Nil];
            [link setProperty:app[@"identifier"] forKey:@"AVNApplication"];
            [rows addObject:link];
        }
    } else {
        self.title = self.specifier.name;
        NSMutableDictionary *database = self.database;
        BOOL defaultAutomatic = ![database[[self storageKey:@"ManualSkip"]] boolValue];
        [rows addObject:[self section:nil note:@"Manual mode waits for the button and never presses Close."]];
        [rows addObject:[self toggle:@"Enabled" feature:@"Enabled" initial:NO]];
        [rows addObject:[self toggle:@"Automatic ads" feature:@"AutomaticAds" initial:defaultAutomatic]];
        [rows addObject:[self toggle:@"Show fast-forward button" feature:@"ManualSkip" initial:YES]];
        NSArray *features = @[
            @[@"Video speed", @"SpeedUpVideo", @YES],
            @[@"Web countdowns", @"CompressTimers", @YES],
            @[@"Gameplay clock", @"AccelerateClock", @YES],
            @[@"Playable assistance", @"AutoInteract", @YES],
            @[@"Close completed ads", @"AutoDismiss", @YES],
            @[@"Block ad redirects", @"BlockRedirects", @YES],
            @[@"Force inline video", @"ForceInline", @NO],
            @[@"Include other native video", @"SpeedNativeVideo", @NO]
        ];
        for (NSArray *feature in features) [rows addObject:[self toggle:feature[0] feature:feature[1] initial:[feature[2] boolValue]]];
    }
    _specifiers = rows.copy;
    return _specifiers;
}
@end
