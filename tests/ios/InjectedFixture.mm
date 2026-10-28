// AdVanish contributions: Copyright (C) 2026 maxblox2999.
// GPL-3.0-only with origin terms; see LICENSE and NOTICE.md.

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import "ASPAdSurface.h"

static NSMutableArray<NSString *> *checks;
static BOOL finished;
static BOOL nativeFinished;
static BOOL webFinished;
static NSMutableDictionary<NSString *, id> *diagnostics;

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
    if (nativeFinished && webFinished) result(nil);
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

@interface ALBaseVideoViewController : UIViewController
@property (nonatomic, strong) InjectedVideoOwner *videoPlayer;
@property (nonatomic, strong) NSObject *currentAd;
@property (nonatomic) BOOL ended;
@property (nonatomic) NSUInteger closes;
@property (nonatomic, strong) UIButton *closeButton;
- (AVPlayer *)avPlayer;
- (BOOL)isVideoFullyWatched;
@end
@implementation ALBaseVideoViewController
- (void)loadView {
    self.view = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.view.backgroundColor = UIColor.blackColor;
    self.currentAd = [NSObject new];
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
    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.frame = CGRectMake(20, 50, 90, 44);
    [self.closeButton setTitle:@"Close" forState:UIControlStateNormal];
    [self.closeButton addTarget:self action:@selector(closeAd) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.closeButton];
    __weak ALBaseVideoViewController *weakSelf = self;
    [NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:video.player.currentItem
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) { weakSelf.ended = YES; }];
}
- (AVPlayer *)avPlayer { return self.videoPlayer.videoView.player; }
- (BOOL)isVideoFullyWatched { return self.ended; }
- (void)closeAd { self.closes += 1; }
@end

@interface InjectedDelegate : UIResponder <UIApplicationDelegate, WKNavigationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) AVPlayer *ordinaryPlayer;
@property (nonatomic, strong) WKWebView *web;
@end
@implementation InjectedDelegate
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    diagnostics[@"webNavigation"] = @"finished";
    diagnostics[@"nativeWebAtNavigation"] = nativeWebState(webView);
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
