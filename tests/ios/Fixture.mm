#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import "ASPAdSurface.h"
#import "ASPManualSkip.h"

static NSMutableArray<NSString *> *checks;
static BOOL finished;

static void result(NSString *failure) {
    if (finished) return;
    finished = YES;
    NSDictionary *report = @{
        @"passed": @(!failure),
        @"checks": checks,
        @"failure": failure ?: @"",
        @"scope": @"iOS Simulator, production native code and a mock SDK; no real ad reward verification"
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/result.json"];
    [data writeToFile:path atomically:YES];
    NSLog(@"AdVanish fixture: %@", failure ?: @"passed");
}

static BOOL check(BOOL condition, NSString *name) {
    if (!condition) {
        result(name);
        return NO;
    }
    [checks addObject:name];
    return YES;
}

static void waitUntil(BOOL (^condition)(void), NSTimeInterval deadline, void (^next)(void)) {
    if (finished) return;
    if (condition()) {
        next();
    } else if ([NSProcessInfo processInfo].systemUptime >= deadline) {
        result(@"Timed out waiting for fixture playback or UIKit activation");
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 20), dispatch_get_main_queue(), ^{
            waitUntil(condition, deadline, next);
        });
    }
}

@interface FixtureVideoView : UIView
@property (nonatomic, strong) AVPlayer *player;
@end
@implementation FixtureVideoView
+ (Class)layerClass { return [AVPlayerLayer class]; }
- (void)setPlayer:(AVPlayer *)player { [(AVPlayerLayer *)self.layer setPlayer:player]; }
- (AVPlayer *)player { return [(AVPlayerLayer *)self.layer player]; }
@end

@interface FixtureVideoOwner : NSObject
@property (nonatomic, strong) FixtureVideoView *videoView;
@end
@implementation FixtureVideoOwner
@end

// Only the ownership getters and completion flag are mocked. AVPlayer, views,
// window discovery and the floating button run the production implementation.
@interface ALBaseVideoViewController : UIViewController
@property (nonatomic, strong) FixtureVideoOwner *videoPlayer;
@property (nonatomic, strong) NSObject *currentAd;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic) NSUInteger closes;
@property (nonatomic) BOOL ended;
@property (nonatomic) BOOL rewardPending;
- (AVPlayer *)avPlayer;
- (BOOL)isVideoFullyWatched;
@end
@implementation ALBaseVideoViewController
- (void)loadView {
    self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor = UIColor.blackColor;
    self.currentAd = [NSObject new];
    self.rewardPending = YES;
    self.videoPlayer = [FixtureVideoOwner new];
    FixtureVideoView *video = [[FixtureVideoView alloc] initWithFrame:self.view.bounds];
    video.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"fixture" withExtension:@"mp4"];
    video.player = [AVPlayer playerWithURL:url];
    video.player.muted = YES;
    self.videoPlayer.videoView = video;
    [self.view addSubview:video];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(20, 50, 90, 44);
    [close setTitle:@"Close" forState:UIControlStateNormal];
    [close addTarget:self action:@selector(closeAd) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];
    self.closeButton = close;
    __weak ALBaseVideoViewController *weakSelf = self;
    [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
        object:video.player.currentItem queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
        weakSelf.ended = YES;
    }];
}
- (AVPlayer *)avPlayer { return self.videoPlayer.videoView.player; }
- (BOOL)isVideoFullyWatched { return self.ended; }
- (void)closeAd { self.closes += 1; }
@end

static UIButton *skipButton(void) {
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (![window isKindOfClass:NSClassFromString(@"ASPSkipWindow")] || window.hidden) continue;
        for (UIView *view in window.rootViewController.view.subviews) {
            if ([view isKindOfClass:UIButton.class]) return (UIButton *)view;
        }
    }
    return nil;
}

static void runFixture(ALBaseVideoViewController *owner) {
    ASPManualSkipTrackController(owner);
    ASPManualSkipConfigure(YES);
    [owner.avPlayer play];
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 20;
    waitUntil(^BOOL {
        return UIApplication.sharedApplication.applicationState == UIApplicationStateActive && skipButton() &&
            owner.avPlayer.timeControlStatus == AVPlayerTimeControlStatusPlaying &&
            CMTimeGetSeconds(owner.avPlayer.currentTime) > 0.1;
    }, deadline, ^{
        UIButton *button = skipButton();
        if (!check(owner.avPlayer.rate == 1 && CMTimeGetSeconds(owner.avPlayer.currentTime) < 5,
                   @"Unpressed manual mode preserves native playback")) return;
        ASPAdSurface *surface = ASPFindAdSurface(@[owner.view.window], NO);
        if (!check(surface.owner == owner && [surface.players containsObject:owner.avPlayer] && !surface.incomplete,
                   @"Visible SDK-owned native player is discovered")) return;
        [button sendActionsForControlEvents:UIControlEventTouchUpInside];
        waitUntil(^BOOL { return owner.ended; }, deadline, ^{
            if (!check(CMTimeGetSeconds(owner.avPlayer.currentTime) >= 11.95 && owner.avPlayer.rate == 0,
                       @"Manual native seek reaches a real player end event")) return;
            waitUntil(^BOOL { return [button.currentTitle isEqualToString:@"Skip current ad"]; }, deadline, ^{
                [button sendActionsForControlEvents:UIControlEventTouchUpInside];
                if (!check(owner.closes == 0 && owner.rewardPending,
                           @"Completed video cannot activate SDK Close while its reward is pending")) return;
                if (!check([button.currentTitle isEqualToString:@"No eligible video"],
                           @"A second press reports an ended video without closing it")) return;
                // The normal SDK/app remains free to close on its own.
                [owner.closeButton sendActionsForControlEvents:UIControlEventTouchUpInside];
                if (!check(owner.closes == 1, @"The app's own Close control remains functional")) return;
                result(nil);
            });
        });
    });
}

@interface FixtureDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation FixtureDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    checks = [NSMutableArray array];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    ALBaseVideoViewController *owner = [ALBaseVideoViewController new];
    self.window.rootViewController = owner;
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{ runFixture(owner); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 25 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        result(@"Fixture deadline exceeded");
    });
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(FixtureDelegate.class));
    }
}
