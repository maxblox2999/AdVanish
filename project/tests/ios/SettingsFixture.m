// Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.
#import <UIKit/UIKit.h>
#import "../../settings/AVNSettings.m"

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
    @try {
        NSString *framework = [NSBundle bundleForClass:PSListController.class].bundlePath;
        require([framework containsString:@"/System/Library/PrivateFrameworks/Preferences.framework"],
            @"The controller uses Apple's real simulator Preferences framework");
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
        require(root.specifiers.count == 4, @"Reentrant title updates build root rows without recursion");
        self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:root];
        self.window.rootViewController = navigation;
        [self.window makeKeyAndVisible];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            @try {
                [root.view layoutIfNeeded];
                require(root.isViewLoaded && root.view.window == self.window, @"The root Settings page opens and lays out");
                PSSpecifier *link = root.specifiers.lastObject;
                require([[link propertyForKey:@"AVNApplication"] isEqual:@"com.maxblox2999.fixture"], @"App rows retain their bundle identifier");
                AVNSettingsController *child = [AVNSettingsController new];
                child.specifier = link;
                [navigation pushViewController:child animated:NO];
                [child.view layoutIfNeeded];
                require(child.specifiers.count == 12 && child.view.window == self.window, @"The app Settings page opens with every control");
                PSSpecifier *enabled = child.specifiers[1];
                require([[enabled propertyForKey:@"AVNKey"] isEqual:@"enabled-com.maxblox2999.fixture"], @"Existing app-enabled preference keys are preserved");
                require([[child valueForControl:enabled] respondsToSelector:@selector(boolValue)], @"Switch values load without invalid dictionary access");
                [navigation popViewControllerAnimated:NO];
                [root.view layoutIfNeeded];
                require(root.specifiers.count == 4, @"Returning to the root rebuilds a usable row cache");
                PSSpecifier *invalid = [PSSpecifier groupSpecifierWithName:@"Invalid"];
                [invalid setProperty:@YES forKey:@"AVNApplication"];
                child.specifier = invalid;
                require(child.avnApplicationIdentifier == nil, @"Malformed application metadata is ignored");
                [child changeValue:@YES forControl:invalid];
                require(YES, @"Missing switch keys do not write or crash");
                record(nil);
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
