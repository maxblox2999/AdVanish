// Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.
#import <UIKit/UIKit.h>
#import "../../settings/AVNSettings.m"
#import "ASPStorePolicy.h"

static NSMutableArray *checks;
static BOOL finished;
static void record(NSString *failure) {
    if (finished) return;
    finished = YES;
    NSDictionary *report = @{@"passed": @(!failure), @"failure": failure ?: @"",
        @"checks": checks ?: @[], @"scope": @"Production Settings controller and real simulator Preferences.framework; physical PreferenceLoader remains unverified"};
    NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/result.json"] atomically:YES];
}
static void require(BOOL value, NSString *name) {
    if (!value) [NSException raise:@"FixtureFailure" format:@"%@", name];
    [checks addObject:name];
    NSData *progress = [NSJSONSerialization dataWithJSONObject:@{@"lastCheck": name, @"checks": checks} options:0 error:nil];
    [progress writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/settings-progress.json"] atomically:YES];
}

@interface ThrowingProxy : NSObject
@end
@implementation ThrowingProxy
- (id)value { [NSException raise:@"Unavailable" format:@"Registry unavailable"]; return nil; }
- (NSInteger)primitive { return 1; }
@end

@interface ReentrantSettingsController : AVNSettingsController
@property (nonatomic) NSUInteger titleDepth;
@end
@implementation ReentrantSettingsController
- (void)setTitle:(NSString *)title {
    if (++self.titleDepth > 8) [NSException raise:@"FixtureFailure" format:@"Recursive title/specifier construction"];
    [self specifiers];
    [super setTitle:title];
    self.titleDepth -= 1;
}
- (NSArray<NSString *> *)preferencePaths {
    return @[[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/preferences.plist"]];
}
- (NSArray *)avnInstalledApplications {
    return @[@{@"identifier": @"com.maxblox2999.fixture", @"title": @"Fixture game"}];
}
@end

@interface AVNSettingsFixtureDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation AVNSettingsFixtureDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    checks = NSMutableArray.array;
    [NSFileManager.defaultManager removeItemAtPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/preferences.plist"] error:nil];
    @try {
        NSString *framework = [NSBundle bundleForClass:PSListController.class].bundlePath;
        require([framework containsString:@"/System/Library/PrivateFrameworks/Preferences.framework"],
            @"The controller uses Apple's real simulator Preferences framework");
        require(ASPApplicationHost(@"com.example.game", @"/private/var/containers/Bundle/Game.app"),
            @"User applications can host the runtime");
        require(!ASPApplicationHost(@"com.apple.springboard", @"/System/Library/CoreServices/SpringBoard.app") &&
            !ASPApplicationHost(@"com.apple.Preferences", @"/Applications/Preferences.app") &&
            !ASPApplicationHost(@"com.example.extension", @"/Game.app/PlugIns/Widget.appex"),
            @"System processes and extensions cannot host floating controls");
        require(ASPAppStoreURL([NSURL URLWithString:@"itms-apps://itunes.apple.com/app/id1"]) &&
            ASPAppStoreURL([NSURL URLWithString:@"https://apps.apple.com/app/id1"]) &&
            !ASPAppStoreURL([NSURL URLWithString:@"https://apps.apple.com.evil.test/app/id1"]) &&
            !ASPAppStoreURL([NSURL URLWithString:@"https://example.com"]),
            @"Store URL matching excludes ordinary and lookalike hosts");
        ThrowingProxy *proxy = [ThrowingProxy new];
        require(AVNSettingsObject(proxy, @"value") == nil, @"An unavailable registry getter is contained");
        require(AVNSettingsObject(proxy, @"primitive") == nil, @"Primitive private getters are never treated as object pointers");
        require(AVNSettingsObject(proxy, @"missing") == nil, @"Missing private selectors are handled");
        AVNSettingsController *real = [AVNSettingsController new];
        require(real.specifiers.count >= 3, @"The production root builds with the simulator app registry");
        require([real.specifiers isKindOfClass:NSMutableArray.class], @"Preferences receives a mutable row cache");

        ReentrantSettingsController *root = [ReentrantSettingsController new];
        root.specifier = [PSSpecifier preferenceSpecifierNamed:@"AdVanish" target:nil set:NULL get:NULL detail:Nil cell:PSLinkCell edit:Nil];
        root.title = @"AdVanish";
        require(root.specifiers.count == 5, @"Reentrant title updates build root rows without recursion");
        self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:root];
        self.window.rootViewController = navigation;
        [self.window makeKeyAndVisible];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            @try {
                [root.view layoutIfNeeded];
                require(root.isViewLoaded && root.view.window == self.window, @"The root Settings page opens and lays out");
                PSSpecifier *link = nil;
                for (PSSpecifier *row in root.specifiers) {
                    if ([row propertyForKey:@"AVNApplication"]) { link = row; break; }
                }
                require([[link propertyForKey:@"AVNApplication"] isEqual:@"com.maxblox2999.fixture"], @"App rows retain their bundle identifier");
                NSUInteger enabledSection = [root.specifiers indexOfObjectPassingTest:^BOOL(PSSpecifier *row, NSUInteger index, BOOL *stop) {
                    return [row.name isEqual:@"Enabled apps"];
                }];
                require(enabledSection != NSNotFound && [root.specifiers indexOfObject:link] > enabledSection,
                    @"An app with no stored key is listed as enabled");
                AVNSettingsController *child = [ReentrantSettingsController new];
                child.specifier = link;
                [navigation pushViewController:child animated:NO];
                [child.view layoutIfNeeded];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                @try {
                [child.view layoutIfNeeded];
                require(child.specifiers.count == 16, [NSString stringWithFormat:@"The app Settings page has every control (rows=%lu, app=%@)", (unsigned long)child.specifiers.count, child.avnApplicationIdentifier]);
                require(child.view.window == self.window, @"The app Settings page is attached to the window");
                NSMutableArray *groups = NSMutableArray.array;
                for (PSSpecifier *row in child.specifiers) {
                    if (![row propertyForKey:@"AVNKey"]) [groups addObject:row.name ?: @""];
                }
                require([groups isEqual:@[@"This app", @"Ad playback", @"Video", @"Ad countdowns", @"Completion"]], @"Per-app controls retain the categorized layout");
                PSSpecifier *enabled = child.specifiers[1];
                require([[enabled propertyForKey:@"AVNKey"] isEqual:@"enabled-com.maxblox2999.fixture"], @"Existing app-enabled preference keys are preserved");
                require([[child valueForControl:enabled] respondsToSelector:@selector(boolValue)], @"Switch values load without invalid dictionary access");
                [child changeValue:@YES forControl:enabled];
                PSSpecifier *automatic = child.specifiers[3];
                PSSpecifier *button = child.specifiers[4];
                [child changeValue:@YES forControl:button];
                require([child.database[@"com.maxblox2999.fixture-AutomaticAds"] isEqual:@YES],
                    @"Showing the button never changes the current automatic policy");
                PSSpecifier *store = child.specifiers.lastObject;
                require([[store propertyForKey:@"AVNKey"] isEqual:@"com.maxblox2999.fixture-HideAppStore"] &&
                    [[child valueForControl:store] boolValue], @"App Store hiding defaults on and uses an app-specific key");
                [child changeValue:@NO forControl:store];
                require(![child.database[@"com.maxblox2999.fixture-HideAppStore"] boolValue],
                    @"App Store hiding can be disabled separately");
                [child changeValue:@NO forControl:automatic];
                [child changeValue:@YES forControl:button];
                NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:child.preferencePaths.firstObject];
                require([saved[@"enabled-com.maxblox2999.fixture"] boolValue], @"Enabling an app persists the runtime preference");
                require([saved[@"com.maxblox2999.fixture-AutomaticAds"] isEqual:@NO] &&
                    [saved[@"com.maxblox2999.fixture-ManualSkip"] isEqual:@YES], @"Showing the manual button preserves explicit manual mode");
                NSString *fallback = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/fallback.plist"];
                [@{@"fallback-enabled": @YES, @"com.maxblox2999.fixture-AutomaticAds": @YES} writeToFile:fallback atomically:YES];
                NSDictionary *merged = ASPReadPreferencesAtPaths(@[child.preferencePaths.firstObject, fallback]);
                require([merged[@"fallback-enabled"] boolValue] && [merged[@"com.maxblox2999.fixture-AutomaticAds"] isEqual:@NO],
                    @"Fallback preference keys survive while preferred values retain priority");
                NSDictionary *runtimeValues = ASPApplicationPreferences(merged, @"com.maxblox2999.fixture");
                require(ASPPreferenceFlag(runtimeValues, @"Enabled", YES) &&
                    ASPPreferenceFlag(runtimeValues, @"AppEnabled", NO), @"Jailbreak configuration resolves the master and app enable switches");
                require(!ASPAutomaticAdsEnabled(runtimeValues), @"Jailbreak configuration preserves explicit manual mode");
                require(!ASPAutomaticAdsEnabled(@{@"ManualSkip": @YES}) &&
                    ASPAutomaticAdsEnabled(@{}) && ASPAutomaticAdsEnabled(@{@"ManualSkip": @YES, @"AutomaticAds": @YES}),
                    @"Legacy button preferences and explicit automatic mode resolve consistently");
                require(ASPPreferenceFlag(ASPApplicationPreferences(@{}, @"com.maxblox2999.fixture"), @"AppEnabled", NO),
                    @"Apps stay enabled when no enable preference exists");
                require(!ASPPreferenceFlag(ASPApplicationPreferences(@{@"enabled-com.maxblox2999.fixture": @NO}, @"com.maxblox2999.fixture"), @"AppEnabled", YES),
                    @"An explicit disable preference still wins");
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), dispatch_get_main_queue(), ^{
                @try {
                [child.view layoutIfNeeded];
                require(child.specifiers.count == 16 && child.view.window == self.window, @"Saved switches reload without invalidating Settings rows");
                [navigation popViewControllerAnimated:NO];
                [root.view layoutIfNeeded];
                require(root.specifiers.count == 5, @"Returning to the root rebuilds a usable row cache");
                PSSpecifier *invalid = [PSSpecifier groupSpecifierWithName:@"Invalid"];
                [invalid setProperty:@YES forKey:@"AVNApplication"];
                child.specifier = invalid;
                require(child.avnApplicationIdentifier == nil, @"Malformed application metadata is ignored");
                [child changeValue:@YES forControl:invalid];
                require(YES, @"Missing switch keys do not write or crash");
                record(nil);
                } @catch (NSException *exception) { record(exception.reason); }
                });
                } @catch (NSException *exception) { record(exception.reason); }
                });
            } @catch (NSException *exception) {
                record(exception.reason);
            }
        });
    } @catch (NSException *exception) {
        record(exception.reason);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ record(@"Settings fixture timed out"); });
    return YES;
}
@end
static void AVNSettingsException(NSException *exception) {
    record([NSString stringWithFormat:@"%@: %@\\n%@", exception.name, exception.reason, exception.callStackSymbols]);
}
int main(int argc, char **argv) {
    @autoreleasepool {
        checks = NSMutableArray.array;
        NSSetUncaughtExceptionHandler(AVNSettingsException);
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AVNSettingsFixtureDelegate.class));
    }
}
