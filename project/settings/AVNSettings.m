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
- (NSArray<NSString *> *)preferencePaths {
    return ASPPrefsPaths(@"com.34306-sr.adspeed");
}
- (NSMutableDictionary *)database {
    if (!self.cachedValues) {
        NSDictionary *loaded = ASPReadPreferencesAtPaths(self.preferencePaths);
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
    id key = [control propertyForKey:@"AVNKey"];
    if (![key isKindOfClass:NSString.class] || ![key length] || !value) return;
    NSMutableDictionary *database = self.database.mutableCopy;
    if ([key isEqualToString:[self storageKey:@"ManualSkip"]]) {
        NSString *automatic = [self storageKey:@"AutomaticAds"];
        if (!database[automatic]) database[automatic] = @(![database[key] boolValue]);
    }
    database[key] = value;
    NSString *file = self.preferencePaths.firstObject;
    [NSFileManager.defaultManager createDirectoryAtPath:file.stringByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:nil error:nil];
    if (![database writeToFile:file atomically:YES]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"AdVanish" message:@"Could not save settings." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        self.cachedValues = database;
    }
    __weak AVNSettingsController *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        AVNSettingsController *controller = weakSelf;
        if (controller && [controller.specifiers containsObject:control]) {
            [controller reloadSpecifier:control animated:NO];
        }
    });
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
    [super viewWillAppear:animated];
    if (!self.avnApplicationIdentifier.length) {
        __weak AVNSettingsController *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            AVNSettingsController *controller = weakSelf;
            if (!controller.viewIfLoaded.window || controller.avnApplicationIdentifier.length) return;
            controller->_specifiers = nil;
            [controller reloadSpecifiers];
        });
    }
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *rows = NSMutableArray.array;
    if (!self.avnApplicationIdentifier.length) {
        [rows addObject:[self section:@"AdVanish" note:@"Enable the apps you want to accelerate."]];
        [rows addObject:[self toggle:@"Enabled" feature:@"Enabled" initial:YES]];
        NSArray *applications = self.avnInstalledApplications;
        for (NSNumber *enabled in @[@YES, @NO]) {
            [rows addObject:[self section:enabled.boolValue ? @"Enabled apps" : @"Not enabled"
                note:enabled.boolValue ? @"16x speed applies inside enabled apps." : nil]];
            for (NSDictionary *app in applications) {
                NSString *key = [@"enabled-" stringByAppendingString:app[@"identifier"]];
                if ([self.database[key] boolValue] != enabled.boolValue) continue;
                PSSpecifier *link = [PSSpecifier preferenceSpecifierNamed:app[@"title"] target:self set:NULL get:NULL
                    detail:AVNSettingsController.class cell:PSLinkCell edit:Nil];
                [link setProperty:@YES forKey:@"isController"];
                [link setProperty:app[@"identifier"] forKey:@"AVNApplication"];
                [rows addObject:link];
            }
        }
    } else {
        BOOL defaultAutomatic = ![self.database[[self storageKey:@"ManualSkip"]] boolValue];
        [rows addObject:[self section:@"This app" note:@"Reopen the app after changing settings."]];
        [rows addObject:[self toggle:@"Enabled" feature:@"Enabled" initial:NO]];
        [rows addObject:[self section:@"Ad playback" note:@"Automatic ads runs without a press. When off, use the fast-forward button."]];
        [rows addObject:[self toggle:@"Automatic ads" feature:@"AutomaticAds" initial:defaultAutomatic]];
        [rows addObject:[self toggle:@"Show fast-forward button" feature:@"ManualSkip" initial:YES]];
        [rows addObject:[self section:@"Video" note:@"16x playback with lower-rate fallback when required."]];
        [rows addObject:[self toggle:@"Video speed" feature:@"SpeedUpVideo" initial:YES]];
        [rows addObject:[self toggle:@"Force inline video" feature:@"ForceInline" initial:NO]];
        [rows addObject:[self toggle:@"Include other native video" feature:@"SpeedNativeVideo" initial:NO]];
        [rows addObject:[self section:@"Ad countdowns" note:@"Accelerates supported web timers and gameplay clocks. Native SDK and server timers may remain unchanged."]];
        [rows addObject:[self toggle:@"Web countdowns" feature:@"CompressTimers" initial:YES]];
        [rows addObject:[self toggle:@"Gameplay clock" feature:@"AccelerateClock" initial:YES]];
        [rows addObject:[self section:@"Completion" note:@"Automatic mode assists supported playables. Closing waits for SDK eligibility; rewards remain controlled by the app."]];
        [rows addObject:[self toggle:@"Playable assistance" feature:@"AutoInteract" initial:YES]];
        [rows addObject:[self toggle:@"Close completed ads" feature:@"AutoDismiss" initial:YES]];
        [rows addObject:[self toggle:@"Block ad redirects" feature:@"BlockRedirects" initial:YES]];
    }
    _specifiers = rows;
    return _specifiers;
}
@end
