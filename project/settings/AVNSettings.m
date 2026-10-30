// Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.

#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <objc/message.h>
#import "../ASPPaths.h"


static id AVNSettingsObject(id receiver, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    @try {
        NSMethodSignature *signature = [receiver methodSignatureForSelector:selector];
        if (!signature || signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') return nil;
        return ((id (*)(id, SEL))objc_msgSend)(receiver, selector);
    } @catch (NSException *exception) {
        return nil;
    }
}

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
- (NSString *)avnApplicationIdentifier {
    id value = [self.specifier propertyForKey:@"AVNApplication"];
    return [value isKindOfClass:NSString.class] ? value : nil;
}
- (NSString *)storageKey:(NSString *)feature {
    NSString *application = self.avnApplicationIdentifier;
    if (!application.length) return feature;
    if ([feature isEqualToString:@"Enabled"]) return [@"enabled-" stringByAppendingString:application];
    return [NSString stringWithFormat:@"%@-%@", application, feature];
}
- (id)valueForControl:(PSSpecifier *)control {
    id key = [control propertyForKey:@"AVNKey"];
    id saved = [key isKindOfClass:NSString.class] ? self.database[key] : nil;
    return saved ?: [control propertyForKey:@"default"];
}
- (void)changeValue:(id)value forControl:(PSSpecifier *)control {
    NSMutableDictionary *database = self.database.mutableCopy;
    NSString *key = [control propertyForKey:@"AVNKey"];
    if ([key isEqualToString:[self storageKey:@"ManualSkip"]]) {
        NSString *automatic = [self storageKey:@"AutomaticAds"];
        if (!database[automatic]) database[automatic] = @(![database[key] boolValue]);
    }
    if (![key isKindOfClass:NSString.class] || !key.length || !value) return;
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
- (NSArray<NSDictionary *> *)avnInstalledApplications {
    Class registry = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = AVNSettingsObject(registry, @"defaultWorkspace");
    id collection = AVNSettingsObject(workspace, @"allApplications");
    if (![collection isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *result = NSMutableArray.array;
    for (id proxy in collection) {
        id type = AVNSettingsObject(proxy, @"applicationType");
        id identifier = AVNSettingsObject(proxy, @"applicationIdentifier");
        id name = AVNSettingsObject(proxy, @"localizedName");
        if (![type isKindOfClass:NSString.class] || ![type isEqualToString:@"User"] ||
            ![identifier isKindOfClass:NSString.class] || ![identifier length]) continue;
        [result addObject:@{@"identifier": identifier,
            @"title": [name isKindOfClass:NSString.class] && [name length] ? name : identifier}];
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
    if (!self.avnApplicationIdentifier.length) {
        [rows addObject:[self section:nil note:@"maxblox2999"]];
        [rows addObject:[self toggle:@"Enabled" feature:@"Enabled" initial:YES]];
        [rows addObject:[self section:@"Apps" note:@"Changes apply after reopening the app."]];
        for (NSDictionary *app in self.avnInstalledApplications) {
            PSSpecifier *link = [PSSpecifier preferenceSpecifierNamed:app[@"title"] target:nil set:NULL get:NULL
                detail:AVNSettingsController.class cell:PSLinkCell edit:Nil];
            [link setProperty:app[@"identifier"] forKey:@"AVNApplication"];
            [rows addObject:link];
        }
    } else {
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
    _specifiers = rows;
    return _specifiers;
}
@end
