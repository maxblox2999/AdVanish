// AdVanish contributions: Copyright (C) 2026 maxblox2999.
// GPL-3.0-only with origin terms; see LICENSE and NOTICE.md.

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import "ASPAdSurface.h"
#import "ASPAdCompletion.h"

static NSMutableArray<NSString *> *checks;
static BOOL finished;
static BOOL nativeFinished;
static BOOL webFinished;
static BOOL manualMode;
static __weak UIWindow *fixtureOverlay;
static NSMutableDictionary<NSString *, id> *diagnostics;
static void (^completionChecks)(void);
static BOOL completionChecksStarted;

static void result(NSString *failure) {
    if (finished) return;
    finished = YES;
    NSDictionary *report = @{@"passed": @(!failure), @"checks": checks, @"diagnostics": diagnostics ?: @{},
        @"failure": failure ?: @"", @"scope": @"Loaded production jailed framework and real Objective-C hooks; mock SDK ownership, no real game rewards"};
    NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/result.json"] atomically:YES];
    NSLog(@"Injected fixture result: %@", report);
}

static NSDictionary *errorDetails(NSError *error) {
    if (!error) return @{};
    return @{@"domain": error.domain ?: @"", @"code": @(error.code),
        @"description": error.localizedDescription ?: @"", @"userInfo": error.userInfo.description ?: @""};
}

static NSString *webSnapshotJS(void) {
    return @"(() => {const node=document.querySelector('button');return {"
        "fixture:window.fixture||null,engine:!!window.__adspeed,stats:window.__adspeed?{...window.__adspeed.stats}:null,"
        "visibility:document.visibilityState,hidden:document.hidden,ready:document.readyState,"
        "viewport:[innerWidth,innerHeight],control:node?{label:node.textContent,rect:node.getBoundingClientRect().toJSON()}:null,"
        "pointer:typeof PointerEvent,touch:typeof Touch,touchEvent:typeof TouchEvent,"
        "errors:window.fixtureErrors||[],clock:typeof window.fixtureNativeNow};})()";
}

static NSDictionary *nativeWebState(WKWebView *web) {
    BOOL (*isAd)(WKWebView *) = (BOOL (*)(WKWebView *))dlsym(RTLD_DEFAULT, "ASPManualSkipIsAdWebView");
    NSArray *(*surfaces)(void) = (NSArray *(*)(void))dlsym(RTLD_DEFAULT, "ASPManualSkipAdSurfaces");
    UIWindow *window = web.window;
    NSMutableArray *hits = [NSMutableArray array];
    for (NSUInteger x = 1; x <= 3; x++) {
        for (NSUInteger y = 1; y <= 3; y++) {
            CGPoint local = CGPointMake(web.bounds.size.width * x / 4, web.bounds.size.height * y / 4);
            CGPoint point = [web convertPoint:local toView:window];
            UIView *hit = [window hitTest:point withEvent:nil];
            [hits addObject:@{@"point": NSStringFromCGPoint(point), @"class": hit ? NSStringFromClass(hit.class) : @"nil",
                @"insideWeb": @(hit == web || [hit isDescendantOfView:web])}];
        }
    }
    NSMutableArray *owners = [NSMutableArray array];
    NSArray *activeSurfaces = surfaces ? surfaces() : @[];
    for (ASPAdSurface *surface in activeSurfaces) {
        UIViewController *owner = surface.owner;
        NSArray *webViews = surface.webViews;
        [owners addObject:@{@"owner": owner ? NSStringFromClass(owner.class) : @"nil",
            @"webCount": @(webViews.count), @"containsWeb": @([webViews containsObject:web]),
            @"root": surface.root.description ?: @"nil"}];
    }
    return @{@"applicationState": @(UIApplication.sharedApplication.applicationState), @"onMainThread": @(NSThread.isMainThread),
        @"web": web.description ?: @"nil", @"webHidden": @(web.hidden), @"webAlpha": @(web.alpha),
        @"webInteraction": @(web.userInteractionEnabled), @"window": window.description ?: @"nil",
        @"windowWindow": window.window.description ?: @"nil", @"windowWindowIsSelf": @(window.window == window),
        @"windowRootVisible": @(ASPViewVisibleInSurface(web, window)),
        @"windowHidden": @(window.hidden), @"windowBounds": NSStringFromCGRect(window.bounds),
        @"rootBounds": NSStringFromCGRect(window.rootViewController.viewIfLoaded.bounds),
        @"frame": NSStringFromCGRect(web.frame), @"bounds": NSStringFromCGRect(web.bounds),
        @"windowSceneState": window.windowScene ? @(window.windowScene.activationState) : NSNull.null,
        @"recognizedWeb": isAd ? @(isAd(web)) : NSNull.null, @"surfaces": owners, @"hitTests": hits};
}

static BOOL check(BOOL condition, NSString *name) {
    if (!condition) {
        result(name);
        return NO;
    }
    [checks addObject:name];
    return YES;
}

static void finishIfReady(void) {
    if (!nativeFinished || !webFinished || completionChecksStarted) return;
    completionChecksStarted = YES;
    if (completionChecks) completionChecks();
    else result(nil);
}

static void waitUntil(BOOL (^condition)(void), NSTimeInterval deadline, void (^next)(void)) {
    if (finished) return;
    if (condition()) {
        next();
    } else if (NSProcessInfo.processInfo.systemUptime >= deadline) {
        result(@"Injected fixture timed out");
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 20), dispatch_get_main_queue(), ^{
            waitUntil(condition, deadline, next);
        });
    }
}

@interface InjectedVideoView : UIView
@property (nonatomic, strong) AVPlayer *player;
@end
@implementation InjectedVideoView
+ (Class)layerClass { return AVPlayerLayer.class; }
- (AVPlayer *)player { return [(AVPlayerLayer *)self.layer player]; }
- (void)setPlayer:(AVPlayer *)player { [(AVPlayerLayer *)self.layer setPlayer:player]; }
@end

@interface InjectedVideoOwner : NSObject
@property (nonatomic, strong) InjectedVideoView *videoView;
@end
@implementation InjectedVideoOwner
@end

@interface UIView (InjectedTapFixture)
- (void)al_addTapHandler:(SEL)action toTarget:(id)target;
@end
@implementation UIView (InjectedTapFixture)
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
@interface MARewardedAd : NSObject
@property (nonatomic, weak) id delegate;
@end
@implementation MARewardedAd
@end

static ALMediatedAd *rewardDescriptor(ALAd *creative) {
    ALMediatedAd *ad = [ALMediatedAd new];
    ad.adapterWrapper = [ALMediationAdapterWrapper new];
    ad.adapterWrapper.ad = ad;
    ad.adapterWrapper.adapter = [ALAppLovinMediationAdapter new];
    ad.adapterWrapper.adapter.loadedRewardedAd = creative;
    return ad;
}

@interface ALBaseVideoViewController : UIViewController
@property (nonatomic, strong) InjectedVideoOwner *videoPlayer;
@property (nonatomic, strong) ALAd *currentAd;
@property (nonatomic) BOOL ended;
@property (nonatomic) NSUInteger closes;
@property (nonatomic, strong) UIView *closeButton;
@property (nonatomic, strong) ALMediatedAd *rewardAd;
@property (nonatomic) NSUInteger rewardEvents;
- (AVPlayer *)avPlayer;
- (BOOL)isVideoFullyWatched;
@end
@implementation ALBaseVideoViewController
- (void)loadView {
    self.view = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.view.backgroundColor = UIColor.blackColor;
    self.currentAd = [ALAd new];
    self.videoPlayer = [InjectedVideoOwner new];
    InjectedVideoView *video = [[InjectedVideoView alloc] initWithFrame:self.view.bounds];
    video.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSBundle.mainBundle URLForResource:@"fixture" withExtension:@"mp4"] options:nil];
    AVMutableComposition *composition = [AVMutableComposition composition];
    for (NSUInteger index = 0; index < 8; index++) {
        [composition insertTimeRange:CMTimeRangeMake(kCMTimeZero, CMTimeMakeWithSeconds(12, 600))
                            ofAsset:asset atTime:CMTimeMakeWithSeconds(index * 12, 600) error:nil];
    }
    video.player = [AVPlayer playerWithPlayerItem:[AVPlayerItem playerItemWithAsset:composition]];
    video.player.muted = YES;
    self.videoPlayer.videoView = video;
    [self.view addSubview:video];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(20, 50, 90, 44);
    [close setTitle:@"Close" forState:UIControlStateNormal];
    [close addTarget:self action:@selector(closeAd) forControlEvents:UIControlEventTouchUpInside];
    self.closeButton = close;
    [self.view addSubview:self.closeButton];
    __weak ALBaseVideoViewController *weakSelf = self;
    [NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:video.player.currentItem
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) { weakSelf.ended = YES; }];
}
- (AVPlayer *)avPlayer { return self.videoPlayer.videoView.player; }
- (BOOL)isVideoFullyWatched { return self.ended; }
- (void)closeAd { self.closes += 1; }
- (void)didDisplayAd:(id)ad {}
- (void)didRewardUserForAd:(id)ad withReward:(id)reward { self.rewardEvents += 1; }
@end

@interface InjectedDelegate : UIResponder <UIApplicationDelegate, WKNavigationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) AVPlayer *ordinaryPlayer;
@property (nonatomic, strong) WKWebView *web;
@property (nonatomic) BOOL manualWebReady;
@property (nonatomic) BOOL manualWebStarted;
- (void)startManualWebIfReady;
- (void)runManualNative:(ALBaseVideoViewController *)owner;
- (void)runManualComposite;
- (void)runRegisteredTapChecks;
@end
@implementation InjectedDelegate
- (void)runRegisteredTapChecks {
    UIViewController *presenter = self.window.rootViewController;
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
    [owner didDisplayAd:owner.rewardAd];
    [close al_addTapHandler:@selector(closeAd) toTarget:owner];
    ASPAdCompletionTrackController(owner);
    if (!check(owner.closes == 0, @"The injected framework leaves a registered UIView X untouched before reward")) return;
    UITapGestureRecognizer *gesture = (UITapGestureRecognizer *)close.gestureRecognizers.lastObject;
    [gesture removeTarget:owner action:@selector(closeAd)];
    [owner didRewardUserForAd:owner.rewardAd withReward:[NSObject new]];
    if (!check(owner.closes == 0 && owner.rewardEvents == 1,
               @"The injected target-removal hook preserves rewards and invalidates the removed X action")) return;
    [close removeGestureRecognizer:gesture];
    owner.rewardAd = rewardDescriptor(owner.currentAd);
    [owner didDisplayAd:owner.rewardAd];
    [close al_addTapHandler:@selector(closeAd) toTarget:owner];
    [owner didRewardUserForAd:owner.rewardAd withReward:[NSObject new]];
    ASPAdCompletionTrackController(owner);
    NSUInteger expected = manualMode ? 0 : 1;
    if (!check(owner.closes == expected && owner.rewardEvents == 2,
               manualMode ? @"The injected manual policy forwards a genuine reward without activating UIView X" :
                   @"The injected SDK registration hook reuses the original UIView X action once after genuine reward")) return;
    ASPAdCompletionTrackController(owner);
    if (!check(owner.closes == expected, @"The injected completion poll never repeats a UIView X action")) return;
    [owner.view removeFromSuperview];
    [owner removeFromParentViewController];
    result(nil);
}
- (UIButton *)manualButton {
    if (fixtureOverlay.hidden) return nil;
    for (UIView *view in fixtureOverlay.rootViewController.view.subviews) {
        if ([view isKindOfClass:UIButton.class]) return (UIButton *)view;
    }
    return nil;
}
- (void)startManualWebIfReady {
    if (!manualMode || !nativeFinished || !self.manualWebReady || self.manualWebStarted || finished) return;
    self.manualWebStarted = YES;
    self.web.hidden = NO;
    NSString *baseline = @"return await new Promise(resolve=>{const real=fixtureNativeNow();const virtual=performance.now();"
        "fixtureNativeTimeout(async()=>resolve({elapsed:fixtureNativeNow()-real,virtual:performance.now()-virtual,"
        "interactions:window.__adspeed.stats.interactions,inspection:await window.__adspeed.inspectAsync()}),750);});";
    [self.web callAsyncJavaScript:baseline arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld
        completionHandler:^(id value, NSError *error) {
        diagnostics[@"manualBaseline"] = value ?: errorDetails(error);
        if (!check(!error && [value isKindOfClass:NSDictionary.class], @"Manual WebKit baseline executes")) return;
        NSDictionary *baselineResult = value;
        double real = [baselineResult[@"elapsed"] doubleValue];
        double virtualTime = [baselineResult[@"virtual"] doubleValue];
        if (!check(real >= 700 && virtualTime < real * 2 && [baselineResult[@"interactions"] integerValue] == 0,
                   @"Unpressed manual mode preserves playable time and performs no input")) return;
        if (!check([baselineResult[@"inspection"][@"count"] integerValue] == 1,
                   @"A non-video playable is a supported manual timing candidate")) return;
        UIButton *button = [self manualButton];
        if (!check(button != nil, @"Manual mode exposes the production floating button")) return;
        [button sendActionsForControlEvents:UIControlEventTouchUpInside];
        NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 5;
        waitUntil(^BOOL { return [button.currentTitle isEqualToString:@"Timing requested"]; }, deadline, ^{
            NSString *timing = @"return await new Promise(resolve=>{const real=fixtureNativeNow();const virtual=performance.now();"
                "setTimeout(()=>resolve({elapsed:fixtureNativeNow()-real,virtual:performance.now()-virtual,"
                "interactions:window.__adspeed.stats.interactions,rewards:fixture.rewardCalls,closes:fixture.closes,stage:fixture.stage}),4000);});";
            [self.web callAsyncJavaScript:timing arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld
                completionHandler:^(id measured, NSError *timingError) {
                diagnostics[@"manualTiming"] = measured ?: errorDetails(timingError);
                if (!check(!timingError && [measured isKindOfClass:NSDictionary.class], @"Manually requested WebKit timing executes")) return;
                if (!check([measured[@"elapsed"] doubleValue] < 2000 && [measured[@"virtual"] doubleValue] >= 3000,
                           @"The manual button accelerates the playable's original four-second timer")) return;
                if (!check([measured[@"interactions"] integerValue] == 0 && [measured[@"rewards"] integerValue] == 0 &&
                           [measured[@"closes"] integerValue] == 0 && [measured[@"stage"] isEqualToString:@"tap-ready"],
                           @"Manual playable timing never generates gameplay, reward or Close actions")) return;
                [self runManualComposite];
            }];
        });
    }];
}
- (void)runManualComposite {
    ALBaseVideoViewController *owner = (ALBaseVideoViewController *)self.window.rootViewController;
    self.web.hidden = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC / 4), dispatch_get_main_queue(), ^{
        AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSBundle.mainBundle URLForResource:@"fixture" withExtension:@"mp4"]];
        [owner.avPlayer replaceCurrentItemWithPlayerItem:item];
        self.web.hidden = NO;
        [owner.avPlayer playImmediatelyAtRate:1];
        NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 10;
        waitUntil(^BOOL { return item.status == AVPlayerItemStatusReadyToPlay &&
            owner.avPlayer.timeControlStatus == AVPlayerTimeControlStatusPlaying; }, deadline, ^{
            NSString *baseline = @"return await new Promise(resolve=>{const real=fixtureNativeNow();const virtual=performance.now();"
                "fixtureNativeTimeout(async()=>resolve({elapsed:fixtureNativeNow()-real,virtual:performance.now()-virtual,"
                "inspection:await window.__adspeed.inspectAsync()}),750);});";
            [self.web callAsyncJavaScript:baseline arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld
                completionHandler:^(id value, NSError *error) {
                diagnostics[@"compositeBaseline"] = value ?: errorDetails(error);
                if (!check(!error && [value isKindOfClass:NSDictionary.class], @"The mixed native/playable baseline executes")) return;
                if (!check(owner.avPlayer.rate == 1 && [value[@"virtual"] doubleValue] < [value[@"elapsed"] doubleValue] * 2,
                           @"A mixed owned ad stays at normal speed before a manual press")) return;
                if (!check([value[@"inspection"][@"count"] integerValue] == 1,
                           @"The mixed ad has one native item and one playable timing candidate")) return;
                UIButton *button = [self manualButton];
                [button sendActionsForControlEvents:UIControlEventTouchUpInside];
                waitUntil(^BOOL { return owner.avPlayer.rate == 16 && [button.currentTitle isEqualToString:@"Ad speed requested"]; }, deadline, ^{
                    NSString *timing = @"return await new Promise(resolve=>{const real=fixtureNativeNow();"
                        "setTimeout(()=>resolve({elapsed:fixtureNativeNow()-real,interactions:__adspeed.stats.interactions,"
                        "rewards:fixture.rewardCalls,closes:fixture.closes}),4000);});";
                    [self.web callAsyncJavaScript:timing arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld
                        completionHandler:^(id measured, NSError *timingError) {
                        diagnostics[@"compositeTiming"] = measured ?: errorDetails(timingError);
                        if (!check(!timingError && [measured isKindOfClass:NSDictionary.class] && [measured[@"elapsed"] doubleValue] < 2000,
                                   @"One manual press accelerates both parts of the same SDK-owned ad")) return;
                        if (!check([measured[@"interactions"] integerValue] == 0 && [measured[@"rewards"] integerValue] == 0 &&
                                   [measured[@"closes"] integerValue] == 0, @"Mixed manual acceleration never fabricates input or completion")) return;
                        [owner.avPlayer pause];
                        webFinished = YES;
                        finishIfReady();
                    }];
                });
            }];
        });
    });
}
- (void)runManualNative:(ALBaseVideoViewController *)owner {
    owner.avPlayer.rate = 1;
    NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (!check(owner.avPlayer.rate == 1 && CMTimeGetSeconds(owner.avPlayer.currentTime) <=
                   (NSProcessInfo.processInfo.systemUptime - started) * 2 + 1,
                   @"The production manual-mode AVPlayer hook never accelerates before a press")) return;
        UIButton *button = [self manualButton];
        if (!check(button != nil, @"The manual native request uses the production floating button")) return;
        double before = CMTimeGetSeconds(owner.avPlayer.currentTime);
        [button sendActionsForControlEvents:UIControlEventTouchUpInside];
        NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 15;
        waitUntil(^BOOL { return owner.avPlayer.rate == 16; }, deadline, ^{
            if (!check(CMTimeGetSeconds(owner.avPlayer.currentTime) < before + 1,
                       @"A manual press retains 16x native playback without a seek")) return;
            waitUntil(^BOOL { return owner.ended; }, deadline, ^{
                if (!check(owner.closes == 0 && owner.avPlayer.rate == 0,
                           @"Manual native completion leaves the SDK Close control untouched")) return;
                nativeFinished = YES;
                [self startManualWebIfReady];
            });
        });
    });
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    diagnostics[@"webNavigation"] = @"finished";
    diagnostics[@"nativeWebAtNavigation"] = nativeWebState(webView);
    if (manualMode) {
        self.manualWebReady = YES;
        [self startManualWebIfReady];
        return;
    }
    NSString *script = [NSString stringWithFormat:@"return await new Promise((resolve) => {"
        "const snapshot=()=>({...%@,bridgeBooleanType:typeof bridgeBoolean,bridgeBooleanValue:bridgeBoolean});"
        "const now=typeof fixtureNativeNow==='function'?fixtureNativeNow:Date.now.bind(Date);"
        "const schedule=typeof fixtureNativeTimeout==='function'?fixtureNativeTimeout:setTimeout.bind(window);"
        "const started=now();"
        "function poll() {"
        "try { if (window.fixture&&fixture.complete) { resolve({complete:fixture.complete,movements:fixture.movements,"
        "rewardCalls:fixture.rewardCalls,redirectCalls:fixture.redirectCalls,closes:fixture.closes,"
        "elapsed:fixture.finishedAt-fixture.startedAt,stats:window.__adspeed?{...window.__adspeed.stats}:null,diagnostics:snapshot()}); return; }"
        "if (now()-started>15000) {resolve({runtimeError:'WebKit playable timed out',diagnostics:snapshot()});return;}"
        "schedule(poll,25); } catch(error) {resolve({runtimeError:String(error.stack||error),diagnostics:snapshot()});}"
        "} poll(); });", webSnapshotJS()];
    [webView callAsyncJavaScript:script arguments:@{@"bridgeBoolean": @YES} inFrame:nil inContentWorld:WKContentWorld.pageWorld
        completionHandler:^(id value, NSError *error) {
        if (finished) return;
        diagnostics[@"nativeWebAtCompletion"] = nativeWebState(webView);
        if (error) {
            diagnostics[@"webEvaluationError"] = errorDetails(error);
            [webView evaluateJavaScript:webSnapshotJS() completionHandler:^(id snapshot, NSError *snapshotError) {
                diagnostics[@"webSnapshot"] = snapshot ?: NSNull.null;
                if (snapshotError) diagnostics[@"webSnapshotError"] = errorDetails(snapshotError);
                result(@"The production engine executes inside iOS WebKit");
            }];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                result(@"The production engine executes inside iOS WebKit");
            });
            return;
        }
        diagnostics[@"webResult"] = value ?: NSNull.null;
        if (!check(!error && [value isKindOfClass:NSDictionary.class], @"The production engine executes inside iOS WebKit")) return;
        NSDictionary *web = value;
        if (web[@"runtimeError"]) {
            result([@"WebKit playable: " stringByAppendingString:[web[@"runtimeError"] description]]);
            return;
        }
        NSDictionary *stats = web[@"stats"];
        if (!check([stats[@"rate"] integerValue] == 16 && [stats[@"polls"] integerValue] > 0,
                   @"WebKit runs the production 16x acceleration policy")) return;
        if (!check([stats[@"interactions"] integerValue] == 3 && [web[@"movements"] integerValue] == 6,
                   @"WebKit synthetic input advances original tap, swipe and continue handlers")) return;
        if (!check([web[@"complete"] boolValue] && [web[@"elapsed"] doubleValue] < 4000,
                   @"The playable's original four-second timer completes faster in WebKit")) return;
        if (!check([web[@"rewardCalls"] integerValue] == 0 && [web[@"closes"] integerValue] == 0,
                   @"WebKit never fabricates a reward or game-end event")) return;
        if (!check([web[@"redirectCalls"] integerValue] == 0 && [stats[@"redirectsBlocked"] integerValue] == 2,
                   @"WebKit blocks supported MRAID and window redirects")) return;
        webFinished = YES;
        finishIfReady();
    }];
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    diagnostics[@"webNavigationError"] = errorDetails(error);
    result(@"Injected WebKit fixture navigation failed");
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    diagnostics[@"webProvisionalNavigationError"] = errorDetails(error);
    result(@"Injected WebKit fixture provisional navigation failed");
}
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    diagnostics[@"webProcessTerminated"] = @YES;
    result(@"Injected WebKit content process terminated");
}
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    checks = [NSMutableArray array];
    diagnostics = [NSMutableDictionary dictionary];
    __weak InjectedDelegate *weakSelf = self;
    completionChecks = ^{ [weakSelf runRegisteredTapChecks]; };
    manualMode = [NSBundle.mainBundle.infoDictionary[@"AdVanishManualFixture"] boolValue];
    diagnostics[@"manualMode"] = @(manualMode);
    [NSNotificationCenter.defaultCenter addObserverForName:UIWindowDidBecomeVisibleNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
        if ([notification.object isKindOfClass:NSClassFromString(@"ASPSkipWindow")]) fixtureOverlay = notification.object;
    }];
    float (*rate)(void) = (float (*)(void))dlsym(RTLD_DEFAULT, "ASPSpeedRate");
    if (!check(rate && rate() == 16, @"The jailed framework loads and exposes the shared 16x policy")) return YES;
    WKWebViewConfiguration *config = [WKWebViewConfiguration new];
    WKUserScript *fixtureClock = [[WKUserScript alloc] initWithSource:
        @"window.fixtureNativeNow=performance.now.bind(performance);window.fixtureNativeTimeout=setTimeout.bind(window);"
        "window.fixtureErrors=[];addEventListener('error',event=>fixtureErrors.push({message:String(event.message),line:event.lineno,column:event.colno}));"
        "addEventListener('unhandledrejection',event=>fixtureErrors.push({rejection:String(event.reason)}));"
        injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
    [config.userContentController addUserScript:fixtureClock];
    WKWebView *web = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.web = web;
    web.navigationDelegate = self;
    BOOL injected = NO;
    for (WKUserScript *script in web.configuration.userContentController.userScripts) {
        if ([script.source containsString:@"AdSpeed shared media engine"] &&
            [script.source containsString:@"\"rate\":16"]) injected = YES;
    }
    if (!check(injected, @"The production WebKit initializer installs its 16x engine")) return YES;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    ALBaseVideoViewController *owner = [ALBaseVideoViewController new];
    self.window.rootViewController = owner;
    [self.window makeKeyAndVisible];
    CGRect area = owner.view.bounds;
    web.frame = CGRectMake(0, CGRectGetHeight(area) - 260, CGRectGetWidth(area), 240);
    web.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [owner.view addSubview:web];
    web.hidden = manualMode;
    NSString *html = @"<!doctype html><meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<style>body{margin:0;background:#eee}button{display:block;position:fixed;left:10px;top:20px;width:280px;height:180px}</style>"
        "<script>window.fixture={complete:false,movements:0,rewardCalls:0,redirectCalls:0,closes:0,startedAt:0,finishedAt:0,stage:'script'};"
        "window.mraid={getState(){return 'default'},getPlacementType(){return 'interstitial'},isViewable(){return true},"
        "open(){fixture.redirectCalls++},close(){fixture.closes++}};"
        "window.gameEnd=()=>fixture.rewardCalls++;"
        "function button(label){const node=document.createElement('button');node.textContent=label;document.body.append(node);return node;}"
        "addEventListener('DOMContentLoaded',()=>{fixture.stage='tap-ready';const start=button('Tap to play');start.addEventListener('click',()=>{"
        "fixture.stage='swipe-ready';start.remove();const swipe=button('Swipe right');let startX=0;"
        "swipe.addEventListener('pointerdown',event=>{fixture.stage='pointer-down';startX=event.clientX;});"
        "swipe.addEventListener('pointermove',()=>fixture.movements++);"
        "swipe.addEventListener('pointerup',event=>{fixture.stage='pointer-up';fixture.swipeDistance=event.clientX-startX;if(event.clientX<=startX+50||fixture.movements!==6)return;"
        "fixture.stage='continue-ready';swipe.remove();const next=button('Continue playing');next.addEventListener('click',()=>{fixture.stage='timer-pending';next.remove();"
        "mraid.open('https://apps.apple.com/app/id0');window.open('https://apps.apple.com/app/id0');"
        "fixture.startedAt=fixtureNativeNow();setTimeout(()=>{fixture.finishedAt=fixtureNativeNow();fixture.complete=true;fixture.stage='complete';},4000);"
        "});});});});</script><body></body>";
    [web loadHTMLString:html baseURL:[NSURL URLWithString:@"https://advanish-fixture.invalid/"]];
    self.ordinaryPlayer = [AVPlayer playerWithURL:[NSBundle.mainBundle URLForResource:@"fixture" withExtension:@"mp4"]];
    self.ordinaryPlayer.muted = YES;
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 30;
    waitUntil(^BOOL {
        return application.applicationState == UIApplicationStateActive && owner.view.window &&
            owner.avPlayer.currentItem.status == AVPlayerItemStatusReadyToPlay &&
            self.ordinaryPlayer.currentItem.status == AVPlayerItemStatusReadyToPlay;
    }, deadline, ^{
        self.ordinaryPlayer.rate = 1;
        if (!check(self.ordinaryPlayer.rate == 1, @"The production AVPlayer hook preserves ordinary playback")) return;
        [self.ordinaryPlayer pause];
        if (manualMode) {
            [self runManualNative:owner];
            return;
        }
        owner.avPlayer.rate = 1;
        waitUntil(^BOOL { return owner.avPlayer.rate == 16 || owner.ended; }, deadline, ^{
            if (!check(owner.avPlayer.rate == 16, @"Recognized SDK playback reaches 16x through the production hook")) return;
            owner.avPlayer.rate = 0.5;
            owner.videoPlayer.videoView.hidden = YES;
            waitUntil(^BOOL { return owner.avPlayer.rate == 0.5; }, deadline, ^{
                if (!check(owner.avPlayer.rate == 0.5, @"Hidden playback restores the SDK's latest requested rate")) return;
                owner.videoPlayer.videoView.hidden = NO;
                owner.avPlayer.rate = 1;
                waitUntil(^BOOL { return owner.avPlayer.rate == 16; }, deadline, ^{
                    if (!check(owner.avPlayer.rate == 16, @"Visible playback accelerates again after rate cleanup")) return;
                    waitUntil(^BOOL { return owner.ended; }, deadline, ^{
                        if (!check(CMTimeGetSeconds(owner.avPlayer.currentTime) >= 95.95,
                                   @"Accelerated playback reaches a real end event without seeking")) return;
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                            if (!check(owner.closes == 0, @"Video end alone never dismisses an unverified rewarded ad")) return;
                            nativeFinished = YES;
                            finishIfReady();
                        });
                    });
                });
            });
        });
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 35 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        result(@"Injected fixture deadline exceeded");
    });
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(InjectedDelegate.class));
    }
}
