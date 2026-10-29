// AdVanish contributions: Copyright (C) 2026 maxblox2999.
// GPL-3.0-only with origin terms; see LICENSE and NOTICE.md.

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import "ASPAdSurface.h"
#import "ASPManualSkip.h"
#import "ASPAdCompletion.h"
#import "ASPSpeed.h"

static NSMutableArray<NSString *> *checks;
static BOOL finished;
static __weak UIWindow *fixtureOverlay;

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

@interface UIView (AdVanishTapFixture)
- (void)al_addTapHandler:(SEL)action toTarget:(id)target;
@end
@implementation UIView (AdVanishTapFixture)
- (void)al_addTapHandler:(SEL)action toTarget:(id)target {
    UITapGestureRecognizer *gesture = [[UITapGestureRecognizer alloc] initWithTarget:target action:action];
    gesture.numberOfTapsRequired = 1;
    gesture.numberOfTouchesRequired = 1;
    [self addGestureRecognizer:gesture];
}
@end

@interface ALExitButton : UIView
@end
@implementation ALExitButton
@end

@interface MARewardedAd : NSObject
@property (nonatomic, weak) id delegate;
@end
@implementation MARewardedAd
@end

@interface ALAd : NSObject
@end
@implementation ALAd
@end

@class ALMediationAdapterWrapper;
@interface MAAd : NSObject
@end
@implementation MAAd
@end
@interface ALMediatedAd : MAAd
@property (nonatomic, strong) ALMediationAdapterWrapper *adapterWrapper;
@end
@implementation ALMediatedAd
@end
@interface ALAppLovinMediationAdapter : NSObject
@property (nonatomic, strong) ALAd *loadedRewardedAd;
@end
@implementation ALAppLovinMediationAdapter
@end
@interface ALMediationAdapterWrapper : NSObject
@property (nonatomic, weak) ALMediatedAd *ad;
@property (nonatomic, strong) ALAppLovinMediationAdapter *adapter;
@end
@implementation ALMediationAdapterWrapper
@end

static ALMediatedAd *rewardDescriptor(ALAd *creative) {
    ALMediatedAd *ad = [ALMediatedAd new];
    ad.adapterWrapper = [ALMediationAdapterWrapper new];
    ad.adapterWrapper.ad = ad;
    ad.adapterWrapper.adapter = [ALAppLovinMediationAdapter new];
    ad.adapterWrapper.adapter.loadedRewardedAd = creative;
    return ad;
}

// Only the ownership getters and completion flag are mocked. AVPlayer, views,
// window discovery and the floating button run the production implementation.
@interface ALBaseVideoViewController : UIViewController
@property (nonatomic, strong) FixtureVideoOwner *videoPlayer;
@property (nonatomic, strong) ALAd *currentAd;
@property (nonatomic, strong) UIView *closeButton;
@property (nonatomic) NSUInteger closes;
@property (nonatomic) BOOL ended;
@property (nonatomic) BOOL rewardPending;
@property (nonatomic) NSUInteger rewardEvents;
@property (nonatomic) NSUInteger displayEvents;
@property (nonatomic, strong) id rewardAd;
- (AVPlayer *)avPlayer;
- (BOOL)isVideoFullyWatched;
@end
@implementation ALBaseVideoViewController
- (void)loadView {
    self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor = UIColor.blackColor;
    self.currentAd = [ALAd new];
    self.rewardPending = YES;
    self.videoPlayer = [FixtureVideoOwner new];
    FixtureVideoView *video = [[FixtureVideoView alloc] initWithFrame:self.view.bounds];
    video.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"fixture" withExtension:@"mp4"];
    AVAsset *source = [AVAsset assetWithURL:url];
    AVMutableComposition *composition = [AVMutableComposition composition];
    for (AVAssetTrack *track in [source tracksWithMediaType:AVMediaTypeVideo]) {
        AVMutableCompositionTrack *target = [composition addMutableTrackWithMediaType:AVMediaTypeVideo
            preferredTrackID:kCMPersistentTrackID_Invalid];
        for (NSUInteger repeat = 0; repeat < 8; repeat++) {
            [target insertTimeRange:CMTimeRangeMake(kCMTimeZero, source.duration) ofTrack:track
                atTime:CMTimeMultiply(source.duration, (int32_t)repeat) error:nil];
        }
    }
    video.player = [AVPlayer playerWithPlayerItem:[AVPlayerItem playerItemWithAsset:composition]];
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
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
        ALBaseVideoViewController *owner = weakSelf;
        if (notification.object == owner.avPlayer.currentItem) owner.ended = YES;
    }];
}
- (AVPlayer *)avPlayer { return self.videoPlayer.videoView.player; }
- (BOOL)isVideoFullyWatched { return self.ended; }
- (void)closeAd { self.closes += 1; }
- (id)invalidCloseAction { return self; }
- (void)didDisplayAd:(id)ad { self.displayEvents += 1; }
- (void)didRewardUserForAd:(id)ad withReward:(id)reward {
    self.rewardEvents += 1;
    self.rewardPending = NO;
}
@end

@interface GADFullScreenAdViewController : ALBaseVideoViewController
@end
@implementation GADFullScreenAdViewController
@end

@interface GADInterstitialAd : NSObject
@property (nonatomic, strong) GADFullScreenAdViewController *controller;
@property (nonatomic) NSUInteger presentations;
- (void)presentFromRootViewController:(UIViewController *)presenter;
@end
@implementation GADInterstitialAd
- (void)presentFromRootViewController:(UIViewController *)presenter {
    self.presentations += 1;
    self.controller = [GADFullScreenAdViewController new];
    [presenter addChildViewController:self.controller];
    self.controller.view.frame = presenter.view.bounds;
    [presenter.view addSubview:self.controller.view];
    [self.controller didMoveToParentViewController:presenter];
    NSURL *url = [NSBundle.mainBundle URLForResource:@"fixture" withExtension:@"mp4"];
    [self.controller.avPlayer replaceCurrentItemWithPlayerItem:[AVPlayerItem playerItemWithURL:url]];
}
@end

@interface GADRewardedAd : NSObject
@property (nonatomic, strong) GADFullScreenAdViewController *controller;
@property (nonatomic, weak) UIViewController *fallbackPresenter;
@property (nonatomic, copy) void (^sdkRewardHandler)(void);
@property (nonatomic) NSUInteger presentations;
@property (nonatomic) BOOL receivedNilHandler;
@property (nonatomic) BOOL receivedNilPresenter;
- (void)presentFromRootViewController:(UIViewController *)presenter userDidEarnRewardHandler:(void (^)(void))handler;
- (void)emitSDKReward;
@end
@implementation GADRewardedAd
- (void)presentFromRootViewController:(UIViewController *)presenter userDidEarnRewardHandler:(void (^)(void))handler {
    self.presentations += 1;
    self.receivedNilPresenter = presenter == nil;
    self.receivedNilHandler = handler == nil;
    self.sdkRewardHandler = handler;
    UIViewController *actualPresenter = presenter ?: self.fallbackPresenter;
    if (!self.controller) self.controller = [GADFullScreenAdViewController new];
    [actualPresenter addChildViewController:self.controller];
    self.controller.view.frame = actualPresenter.view.bounds;
    [actualPresenter.view addSubview:self.controller.view];
    [self.controller didMoveToParentViewController:actualPresenter];
    self.controller.currentAd = [ALAd new];
    self.controller.closes = 0;
}
- (void)emitSDKReward {
    if (self.sdkRewardHandler) self.sdkRewardHandler();
}
@end

static BOOL testRegisteredTapClose(UIViewController *presenter) {
    NSArray<NSString *> *names = @[
        @"An unrelated registered tap target cannot close the current ad",
        @"A disabled SDK Close tap stays untouched after reward",
        @"A removed SDK Close gesture stays untouched after reward",
        @"Removing the registered target invalidates automatic Close",
        @"A stale reward cannot activate a new creative's registered Close",
        @"Adding a target invalidates the observed SDK Close registration",
        @"A registered action with an incompatible return type is not invoked",
        @"An unobserved tap is not inferred from the SDK Close getter",
    ];
    for (NSUInteger kind = 0; kind <= names.count; kind++) {
        ALBaseVideoViewController *owner = [ALBaseVideoViewController new];
        [presenter addChildViewController:owner];
        owner.view.frame = presenter.view.bounds;
        [presenter.view addSubview:owner.view];
        [owner didMoveToParentViewController:presenter];
        owner.videoPlayer.videoView.hidden = YES;
        [owner.closeButton removeFromSuperview];
        ALExitButton *close = [[ALExitButton alloc] initWithFrame:CGRectMake(20, 50, 90, 44)];
        close.backgroundColor = UIColor.systemBlueColor;
        owner.closeButton = close;
        [owner.view addSubview:close];
        MARewardedAd *sdk = [MARewardedAd new];
        sdk.delegate = owner;
        owner.rewardAd = rewardDescriptor(owner.currentAd);
        id callbackAd = owner.rewardAd;
        [owner didDisplayAd:callbackAd];
        ALBaseVideoViewController *other = kind == 0 ? [ALBaseVideoViewController new] : nil;
        if (kind == 7) {
            [close addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:owner action:@selector(closeAd)]];
        } else {
            [close al_addTapHandler:kind == 6 ? @selector(invalidCloseAction) : @selector(closeAd) toTarget:other ?: owner];
        }
        UITapGestureRecognizer *gesture = (UITapGestureRecognizer *)close.gestureRecognizers.lastObject;
        ASPAdCompletionTrackController(owner);
        if (!check(owner.closes == 0, @"A registered UIView Close waits for a genuine reward")) return NO;
        if (kind == 1) gesture.enabled = NO;
        if (kind == 2) [close removeGestureRecognizer:gesture];
        if (kind == 3) [gesture removeTarget:owner action:@selector(closeAd)];
        if (kind == 4) {
            owner.currentAd = [ALAd new];
            owner.rewardAd = rewardDescriptor(owner.currentAd);
            [owner didDisplayAd:owner.rewardAd];
        }
        if (kind == 5) [gesture addTarget:owner action:@selector(closeAd)];
        [owner didRewardUserForAd:callbackAd withReward:[NSObject new]];
        ASPAdCompletionTrackController(owner);
        if (kind < names.count) {
            if (!check(owner.closes == 0, names[kind])) return NO;
        } else {
            if (!check(owner.closes == 1 && owner.rewardEvents == 1,
                       @"A genuine matching reward invokes the SDK's registered UIView X action once")) return NO;
            ASPAdCompletionTrackController(owner);
            if (!check(owner.closes == 1, @"Repeated polling cannot repeat a registered UIView Close")) return NO;
            ASPAdSurface *surface = ASPFindAdSurface(@[owner.view.window], YES);
            if (!check(surface.owner == owner && surface.players.count == 0,
                       @"Non-video SDK ownership supports registered Close without an AVPlayer")) return NO;
        }
        [owner.view removeFromSuperview];
        [owner removeFromParentViewController];
    }
    return YES;
}

static void testGoogleRewarded(UIViewController *presenter) {
    __block NSUInteger nilRootRewards = 0;
    GADRewardedAd *nilRoot = [GADRewardedAd new];
    nilRoot.fallbackPresenter = presenter;
    [nilRoot presentFromRootViewController:nil userDidEarnRewardHandler:^{ nilRootRewards += 1; }];
    ASPAdCompletionTrackController(nilRoot.controller);
    [nilRoot emitSDKReward];
    if (!check(nilRoot.presentations == 1 && nilRoot.receivedNilPresenter && nilRootRewards == 1 && nilRoot.controller.closes == 1,
               @"A nil Google root resolves the active legacy window without changing SDK input")) return;
    [nilRoot.controller.view removeFromSuperview];
    [nilRoot.controller removeFromParentViewController];
    __block NSUInteger firstRewards = 0;
    __block NSUInteger secondRewards = 0;
    GADRewardedAd *first = [GADRewardedAd new];
    first.fallbackPresenter = presenter;
    [first presentFromRootViewController:presenter userDidEarnRewardHandler:^{ firstRewards += 1; }];
    ASPAdCompletionTrackController(first.controller);
    if (!check(first.presentations == 1 && first.controller.closes == 0,
               @"Google presentation forwards once and preserves its pending reward")) return;
    [first.controller.view removeFromSuperview];
    [first.controller removeFromParentViewController];
    GADRewardedAd *second = [GADRewardedAd new];
    second.controller = first.controller;
    [second presentFromRootViewController:presenter userDidEarnRewardHandler:^{ secondRewards += 1; }];
    ASPAdCompletionTrackController(second.controller);
    [first emitSDKReward];
    if (!check(firstRewards == 1 && secondRewards == 0 && second.controller.closes == 0,
               @"A stale Google SDK reward is forwarded without dismissing a reused controller")) return;
    [second emitSDKReward];
    if (!check(second.presentations == 1 && secondRewards == 1 && second.controller.closes == 1,
               @"A matching Google SDK reward forwards the app handler and activates Close once")) return;
    ASPAdCompletionTrackController(second.controller);
    if (!check(second.controller.closes == 1, @"Google reward observation cannot duplicate dismissal")) return;
    [second.controller.view removeFromSuperview];
    [second.controller removeFromParentViewController];
    GADRewardedAd *withoutHandler = [GADRewardedAd new];
    [withoutHandler presentFromRootViewController:presenter userDidEarnRewardHandler:nil];
    ASPAdCompletionTrackController(withoutHandler.controller);
    [withoutHandler emitSDKReward];
    if (!check(withoutHandler.presentations == 1 && withoutHandler.receivedNilHandler &&
               withoutHandler.sdkRewardHandler == nil && withoutHandler.controller.closes == 0,
               @"A nil Google reward handler reaches the SDK unchanged")) return;
    [withoutHandler.controller.view removeFromSuperview];
    [withoutHandler.controller removeFromParentViewController];
    if (!testRegisteredTapClose(presenter)) return;
    result(nil);
}

static void runOrdinaryCase(UIViewController *presenter, NSUInteger kind, NSTimeInterval deadline) {
    GADInterstitialAd *ad = [GADInterstitialAd new];
    [ad presentFromRootViewController:presenter];
    [ad.controller.avPlayer play];
    waitUntil(^BOOL { return ad.controller.avPlayer.timeControlStatus == AVPlayerTimeControlStatusPlaying; }, deadline, ^{
        ASPAdCompletionTrackController(ad.controller);
        if (!check(ad.presentations == 1 && ad.controller.closes == 0,
                   @"An available ordinary-ad Close stays untouched before playback completes")) return;
        if (kind == 0) {
            WKWebView *interactive = [[WKWebView alloc] initWithFrame:CGRectMake(0, 200, 100, 100)];
            [ad.controller.view addSubview:interactive];
        } else if (kind == 1) {
            FixtureVideoView *additional = [[FixtureVideoView alloc] initWithFrame:CGRectMake(0, 200, 100, 100)];
            additional.player = [AVPlayer playerWithPlayerItem:[AVPlayerItem playerItemWithAsset:ad.controller.avPlayer.currentItem.asset]];
            [ad.controller.view addSubview:additional];
        }
        ASPAdCompletionTrackController(ad.controller);
        ASPSpeedAcceleratePlayer(ad.controller.avPlayer, ad.controller.view);
        waitUntil(^BOOL { return ad.controller.ended; }, deadline, ^{
            if (kind < 2) {
                NSString *name = kind == 0 ? @"A mixed web phase prevents ordinary-video auto-dismissal" :
                    @"A newly admitted native player prevents ordinary-video auto-dismissal";
                if (!check(ad.controller.closes == 0, name)) return;
                [ad.controller.view removeFromSuperview];
                [ad.controller removeFromParentViewController];
                runOrdinaryCase(presenter, kind + 1, deadline);
                return;
            }
            if (!check(ad.controller.closes == 1 && ad.controller.avPlayer.rate == 0,
                       @"A real ordinary-ad video end activates the eligible SDK Close")) return;
            ASPAdCompletionTrackController(ad.controller);
            if (!check(ad.controller.closes == 1, @"Ordinary-ad completion cannot dismiss twice")) return;
            [ad.controller.view removeFromSuperview];
            [ad.controller removeFromParentViewController];
            testGoogleRewarded(presenter);
        });
    });
}

static void testOrdinaryInterstitial(UIViewController *presenter) {
    GADInterstitialAd *staleAd = [GADInterstitialAd new];
    [staleAd presentFromRootViewController:presenter];
    [staleAd.controller.avPlayer play];
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 8;
    waitUntil(^BOOL { return staleAd.controller.avPlayer.currentItem.status == AVPlayerItemStatusReadyToPlay; }, deadline, ^{
        ASPAdCompletionTrackController(staleAd.controller);
        AVPlayerItem *oldItem = staleAd.controller.avPlayer.currentItem;
        AVPlayerItem *replacement = [AVPlayerItem playerItemWithAsset:oldItem.asset];
        [staleAd.controller.avPlayer replaceCurrentItemWithPlayerItem:replacement];
        [NSNotificationCenter.defaultCenter postNotificationName:AVPlayerItemDidPlayToEndTimeNotification object:oldItem];
        if (!check(staleAd.controller.closes == 0, @"A stale item end cannot dismiss an ordinary interstitial")) return;
        [staleAd.controller.view removeFromSuperview];
        [staleAd.controller removeFromParentViewController];
        runOrdinaryCase(presenter, 0, deadline);
    });
}

static UIButton *skipButton(void) {
    if (fixtureOverlay.hidden) return nil;
    for (UIView *view in fixtureOverlay.rootViewController.view.subviews) {
        if ([view isKindOfClass:UIButton.class]) return (UIButton *)view;
    }
    return nil;
}

static void testCompletion(ALBaseVideoViewController *owner, UIButton *button, NSTimeInterval deadline) {
    waitUntil(^BOOL { return owner.ended; }, deadline, ^{
        if (!check(CMTimeGetSeconds(owner.avPlayer.currentTime) >= CMTimeGetSeconds(owner.avPlayer.currentItem.duration) - 0.05 && owner.avPlayer.rate == 0,
                   @"Faster playback reaches a real player end event")) return;
        waitUntil(^BOOL { return [button.currentTitle isEqualToString:@"Fast-forward ad"]; }, deadline, ^{
            [button sendActionsForControlEvents:UIControlEventTouchUpInside];
            if (!check(owner.closes == 0 && owner.rewardPending,
                       @"Completed video cannot activate SDK Close while its reward is pending")) return;
            if (!check([button.currentTitle isEqualToString:@"No supported media"],
                       @"A second press reports an ended video without closing it")) return;
            NSUInteger priorRewards = owner.rewardEvents;
            [owner didRewardUserForAd:[NSObject new] withReward:[NSObject new]];
            if (!check(owner.closes == 0, @"An unrelated reward cannot close the current ad")) return;
            owner.rewardPending = YES;
            [owner didRewardUserForAd:owner.rewardAd withReward:[NSObject new]];
            if (!check(owner.rewardEvents == priorRewards + 2 && owner.closes == 1 && !owner.rewardPending,
                       @"The genuine matching reward is forwarded and activates SDK Close once")) return;
            ASPAdCompletionTrackController(owner);
            if (!check(owner.closes == 1, @"Repeated completion polling cannot duplicate dismissal")) return;
            [(UIControl *)owner.closeButton sendActionsForControlEvents:UIControlEventTouchUpInside];
            if (!check(owner.closes == 2, @"The app's own Close control remains functional")) return;
            testOrdinaryInterstitial(owner);
        });
    });
}

static void testReplacement(ALBaseVideoViewController *owner, UIButton *button, NSTimeInterval deadline) {
    AVPlayerItem *replacement = [AVPlayerItem playerItemWithAsset:owner.avPlayer.currentItem.asset];
    id previousAd = owner.rewardAd;
    owner.currentAd = [ALAd new];
    owner.rewardAd = rewardDescriptor(owner.currentAd);
    [owner didDisplayAd:previousAd];
    [owner didRewardUserForAd:previousAd withReward:[NSObject new]];
    if (!check(owner.closes == 0, @"A delayed old display and reward cannot close a new creative")) return;
    owner.rewardPending = YES;
    [owner didDisplayAd:owner.rewardAd];
    [owner.avPlayer replaceCurrentItemWithPlayerItem:replacement];
    NSTimeInterval replacementStarted = NSProcessInfo.processInfo.systemUptime;
    [owner.avPlayer playImmediatelyAtRate:16];
    waitUntil(^BOOL {
        return owner.avPlayer.rate == 1 && [button.currentTitle isEqualToString:@"Fast-forward ad"];
    }, deadline, ^{
        NSTimeInterval elapsed = NSProcessInfo.processInfo.systemUptime - replacementStarted;
        if (!check(CMTimeGetSeconds(owner.avPlayer.currentTime) <= elapsed * ASPSpeedRate() + 0.5,
                   @"Replacing a creative releases its owned rate without seeking")) return;
        [button sendActionsForControlEvents:UIControlEventTouchUpInside];
        if (!check(owner.avPlayer.rate == 16, @"A new creative accepts a separate manual request")) return;
        testCompletion(owner, button, deadline);
    });
}

static BOOL testCreativeOwnership(ALBaseVideoViewController *owner) {
    id originalCreative = owner.currentAd;
    id originalRewardAd = owner.rewardAd;
    __weak NSObject *releasedCreative;
    @autoreleasepool {
        ALAd *creative = [ALAd new];
        releasedCreative = creative;
        owner.currentAd = creative;
        owner.rewardAd = rewardDescriptor(creative);
        [owner didDisplayAd:owner.rewardAd];
        owner.currentAd = originalCreative;
        owner.rewardAd = originalRewardAd;
    }
    BOOL released = check(releasedCreative == nil, @"Completion observation does not retain a discarded SDK creative");
    ASPAdCompletionTrackController(owner);
    return released;
}

static BOOL testMediatedOwnership(ALBaseVideoViewController *owner) {
    ALMediatedAd *ad = owner.rewardAd;
    if (!check(ad != (id)owner.currentAd && ad.adapterWrapper.adapter.loadedRewardedAd == owner.currentAd,
               @"MAX callback descriptors and AppLovin creative objects have distinct identities")) return NO;
    ALAd *creative = owner.currentAd;
    [owner didDisplayAd:ad];
    ad.adapterWrapper.adapter.loadedRewardedAd = [ALAd new];
    [owner didRewardUserForAd:ad withReward:[NSObject new]];
    ad.adapterWrapper.adapter.loadedRewardedAd = creative;
    ASPAdCompletionTrackController(owner);
    if (!check(owner.closes == 0, @"A reward after adapter retargeting cannot authorize a restored creative")) return NO;
    [owner didDisplayAd:ad];
    ASPAdCompletionConfigure(NO);
    [owner didRewardUserForAd:ad withReward:[NSObject new]];
    if (!check(owner.closes == 0, @"Manual-only completion policy forwards rewards without pressing Close")) return NO;
    owner.rewardAd = rewardDescriptor(creative);
    [owner didDisplayAd:owner.rewardAd];
    ASPAdCompletionConfigure(YES);
    [owner didRewardUserForAd:ad withReward:[NSObject new]];
    ASPAdCompletionTrackController(owner);
    if (!check(owner.closes == 0, @"A replaced MAX descriptor cannot close the current presentation")) return NO;
    owner.rewardPending = YES;
    return YES;
}

static BOOL testWebWindowExposure(ALBaseVideoViewController *owner) {
    UIWindow *window = [[UIWindow alloc] initWithFrame:owner.view.window.bounds];
    window.windowLevel = owner.view.window.windowLevel + 1;
    window.rootViewController = [UIViewController new];
    [window makeKeyAndVisible];
    WKWebView *web = [[WKWebView alloc] initWithFrame:window.bounds];
    [window.rootViewController.view addSubview:web];
    ASPManualSkipTrackWebView(web);
    if (!check(ASPManualSkipWebViewContext(web) == 0,
               @"An exposed unknown SDK web surface retains MRAID discovery")) return NO;
    web.hidden = YES;
    if (!check(ASPManualSkipWebViewContext(web) < 0, @"A hidden unknown SDK web surface is inactive")) return NO;
    web.hidden = NO;
    UIWindow *cover = [[UIWindow alloc] initWithFrame:window.bounds];
    cover.windowLevel = window.windowLevel + 1;
    cover.rootViewController = [UIViewController new];
    cover.rootViewController.view.backgroundColor = UIColor.blackColor;
    [cover makeKeyAndVisible];
    ASPManualSkipTrackController(cover.rootViewController);
    if (!check(ASPManualSkipWebViewContext(web) < 0,
               @"A separate opaque window prevents underlying web authorization")) return NO;
    cover.hidden = YES;
    if (!check(ASPManualSkipWebViewContext(web) == 0,
               @"Removing a covering window restores unknown web discovery")) return NO;
    window.hidden = YES;
    [owner.view.window makeKeyWindow];
    return YES;
}

static void runFixture(ALBaseVideoViewController *owner) {
    ASPManualSkipTrackController(owner);
    ASPManualSkipConfigure(YES);
    ASPAdCompletionConfigure(YES);
    ASPAdCompletionInstallHooks();
    MARewardedAd *sdk = [MARewardedAd new];
    sdk.delegate = owner;
    owner.rewardAd = rewardDescriptor(owner.currentAd);
    [owner didDisplayAd:owner.rewardAd];
    [owner.avPlayer play];
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 20;
    waitUntil(^BOOL {
        return UIApplication.sharedApplication.applicationState == UIApplicationStateActive && skipButton() &&
            owner.avPlayer.timeControlStatus == AVPlayerTimeControlStatusPlaying &&
            CMTimeGetSeconds(owner.avPlayer.currentTime) > 0.1;
    }, deadline, ^{
        UIButton *button = skipButton();
        UIWindow *overlay = button.window;
        if (!check(!overlay.opaque && !overlay.rootViewController.view.opaque &&
                   CGColorGetAlpha(overlay.backgroundColor.CGColor) == 0 &&
                   CGColorGetAlpha(overlay.rootViewController.view.backgroundColor.CGColor) == 0,
                   @"The floating overlay and its root view are explicitly transparent")) return;
        if (!check([overlay hitTest:CGPointMake(20, 200) withEvent:nil] == nil,
                   @"Taps outside the floating button reach the app")) return;
        if (!check(owner.avPlayer.rate == 1 && CMTimeGetSeconds(owner.avPlayer.currentTime) < 5,
                   @"Unpressed manual mode preserves native playback")) return;
        ASPAdSurface *surface = ASPFindAdSurface(@[owner.view.window], NO);
        if (!check(surface.owner == owner && [surface.players containsObject:owner.avPlayer] && !surface.incomplete,
                   @"Visible SDK-owned native player is discovered")) return;
        if (!check(ASPViewVisibleInSurface(owner.videoPlayer.videoView, owner.view.window),
                   @"A window root includes its visible content")) return;
        if (!check(owner.displayEvents == 1, @"The SDK display callback is forwarded unchanged")) return;
        if (!testCreativeOwnership(owner)) return;
        if (!testMediatedOwnership(owner)) return;
        if (!testWebWindowExposure(owner)) return;
        double before = CMTimeGetSeconds(owner.avPlayer.currentTime);
        [button sendActionsForControlEvents:UIControlEventTouchUpInside];
        if (!check(owner.avPlayer.rate == 16 && CMTimeGetSeconds(owner.avPlayer.currentTime) < before + 0.5,
                   @"Manual action requests 16x playback without a time jump")) return;
        owner.videoPlayer.videoView.hidden = YES;
        waitUntil(^BOOL {
            return owner.avPlayer.rate == 1 && [button.currentTitle isEqualToString:@"Fast-forward ad"];
        }, deadline, ^{
            if (!check(owner.avPlayer.rate == 1, @"Hiding the video releases its manual rate")) return;
            owner.videoPlayer.videoView.hidden = NO;
            [button sendActionsForControlEvents:UIControlEventTouchUpInside];
            if (!check(owner.avPlayer.rate == 16, @"Visible playback accepts a new manual request")) return;
            testReplacement(owner, button, deadline);
        });
    });
}

@interface FixtureDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation FixtureDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    checks = [NSMutableArray array];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIWindowDidBecomeVisibleNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
        if ([notification.object isKindOfClass:NSClassFromString(@"ASPSkipWindow")]) fixtureOverlay = notification.object;
    }];
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
