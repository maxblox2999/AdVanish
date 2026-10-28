// AdVanish contributions: Copyright (C) 2026 maxblox2999.
// GPL-3.0-only with origin terms; see LICENSE and NOTICE.md.

// AdVanish. See NOTICE.md for upstream attribution.
// ADSPEED_FORCE_ON enables standalone injection without per-app preferences.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#ifndef ADSPEED_JAILED
#import <substrate.h>
#endif
#import <mach-o/dyld.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <math.h>
#include <atomic>
#include <string.h>
#import "ASPUniversalSkip.h"
#import "ASPManualSkip.h"
#import "ASPSpeed.h"
#import "ASPAdCompletion.h"
#include "AdSpeedWebScript.h"

#pragma mark - Preferences

static NSString *const kKeyMaster     = @"Enabled";        // master on/off, default YES
static NSString *const kKeySpeedVideo = @"SpeedUpVideo";   // speed up ad video, default YES
static NSString *const kKeyWebTimers  = @"CompressTimers"; // compress detected ad JS timers, default YES
static NSString *const kKeyWebClock   = @"AccelerateClock"; // accelerate detected ad clocks, default YES
static NSString *const kKeyForceInline = @"ForceInline";   // force webview video inline (for stuck fullscreen video), default NO
static NSString *const kKeySpeedNative= @"SpeedNativeVideo";// speed every AVPlayer, not just detected ad VCs, default NO
static NSString *const kKeyBypassJB   = @"BypassJailbreak";// jailbreak-detect bypass, default YES
static NSString *const kKeyAppPrefix  = @"enabled-";       // per-app key: enabled-<bundleID>
static NSString *const kKeyManualSkip = @"ManualSkip";

// Runtime state, resolved once at launch.
static BOOL  gActive      = NO;
static BOOL  gSpeedVideo  = YES;
static BOOL  gWebTimers   = NO;
static BOOL  gWebClock    = NO;
static BOOL  gForceInline  = NO;
static BOOL  gSpeedNative  = NO;
static BOOL  gManualSkip = NO;
static BOOL gAutomaticAds = YES;
static BOOL gAutoInteract = YES;
static BOOL gAutoDismiss = YES;
static BOOL gBlockRedirects = YES;
static NSHashTable<WKWebView *> *gWebViews;
static BOOL gPollScheduled;


static NSDictionary *loadPrefs(void) {
    // The Settings panel writes via CFPreferences for the mobile user; read the plist
    // directly so it works regardless of sandbox/CFPreferences quirks. Try rootless
    // first, then rootful.
    NSArray *paths = @[
        @"/var/jb/var/mobile/Library/Preferences/com.34306-sr.adspeed.plist",
        @"/var/mobile/Library/Preferences/com.34306-sr.adspeed.plist",
    ];
    for (NSString *p in paths) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if (d) return d;
    }
    return nil;
}

static BOOL prefBool(NSDictionary *p, NSString *key, BOOL fallback) {
    id v = p[key];
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : fallback;
}

static BOOL automaticAdsPreference(NSDictionary *prefs, NSString *automaticKey, NSString *manualKey) {
    if (prefs[automaticKey]) return prefBool(prefs, automaticKey, YES);
    // Existing explicit manual-mode choices keep requiring the button after upgrading.
    return !prefBool(prefs, manualKey, NO);
}

// Per-app preference key: "<bundleID>-<Suffix>" (e.g. com.x.game-SpeedUpVideo).
static NSString *appKey(NSString *bid, NSString *suffix) {
    return [NSString stringWithFormat:@"%@-%@", bid, suffix];
}

#pragma mark - Debug (build with -DADSPEED_DEBUG)

#ifdef ADSPEED_DEBUG
// Logs to the system log AND to <app sandbox>/tmp/adspeed.log (always writable,
// retrieve it over SSH with:
//   find /var/mobile/Containers/Data/Application -name adspeed.log)
static void aspLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[AdSpeed] %@", msg);
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"adspeed.log"];
    NSString *line = [msg stringByAppendingString:@"\n"];
    // Truncate once per process launch, then append within the launch, so each file
    // only holds the most recent run instead of accumulating across respawns.
    static BOOL truncated = NO;
    FILE *f = fopen(path.UTF8String, truncated ? "a" : "w");
    truncated = YES;
    if (f) { fputs(line.UTF8String, f); fclose(f); }
}

#endif // ADSPEED_DEBUG

// Class dump is opt-in (build with -DADSPEED_DUMP -DADSPEED_DEBUG): calling
// objc_copyClassList crashes some apps (e.g. Idle Sword Master), so keep it out of
// the normal debug build.
#ifdef ADSPEED_DUMP
static void aspDumpAdClasses(void) {
    // Specific tokens only — loose ones (MAX, ISA, MTG, Interstitial) match tons of
    // system classes (MAXpcManager, UISApplicationState, MPS...MTGP32, AVPlayerInterstitial).
    NSArray *kw = @[@"AppLovin", @"ALSdk", @"MAInterstitial", @"MARewarded", @"MANative", @"MAAppOpen",
                    @"IronSource", @"LevelPlay", @"ISInterstitial", @"ISRewardedVideo", @"ISBannerAd",
                    @"Mintegral", @"MTGInterstitial", @"MTGReward", @"MTGBid", @"MTGBanner", @"MTGNative",
                    @"InMobi", @"IMInterstitial", @"IMBanner", @"IMNative", @"IMRewarded",
                    @"UnityAds", @"UADSBanner",
                    @"GADInterstitial", @"GADRewarded", @"GADAppOpen", @"GADNativeAd",
                    @"Vungle", @"AdColony", @"Chartboost", @"PAGInterstitial", @"BUNativeAd",
                    @"Fyber", @"Tapjoy"];
    unsigned int n = 0;
    Class *cls = objc_copyClassList(&n);
    int hits = 0;
    for (unsigned i = 0; i < n; i++) {
        NSString *name = @(class_getName(cls[i]));
        for (NSString *k in kw) {
            if ([name containsString:k]) { aspLog(@"  class: %@", name); hits++; break; }
        }
    }
    free(cls);
    aspLog(@"ad-like classes found: %d", hits);
}
#endif

typedef struct { const char *cls; const char *sel; } AdHook;
static BOOL returnFalse(__unused id object, __unused SEL selector) { return NO; }

static void installHook(const AdHook *hook) {
    Class cls = objc_getClass(hook->cls);
    SEL selector = sel_registerName(hook->sel);
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 2) return;
    char result[16] = {};
    method_getReturnType(method, result, sizeof(result));
    if (strcmp(result, @encode(BOOL)) != 0) return;
    static NSMutableSet<NSString *> *installed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ installed = [NSMutableSet set]; });
    NSString *key = [NSString stringWithFormat:@"%p:%s", (__bridge void *)cls, hook->sel];
    if ([installed containsObject:key]) return;
#ifndef ADSPEED_JAILED
    MSHookMessageEx(cls, selector, (IMP)returnFalse, NULL);
#else
    if (!class_addMethod(cls, selector, (IMP)returnFalse, method_getTypeEncoding(method))) {
        method_setImplementation(class_getInstanceMethod(cls, selector), (IMP)returnFalse);
    }
#endif
    [installed addObject:key];
}

#pragma mark - Jailbreak-detection bypass table

static const AdHook kJailbreakHooks[] = {
    {"BUDeviceHelper", "bu_isJailBroken"},
    {"EBAppLogDeviceHelper", "isJailBroken"},
    {"HMDBUInfo", "isJailBroken"},
    {"MobClick", "isJailbroken"},
    {"MobClick", "isPirated"},
    {"SSEDeviceStatus", "jailBroken"},
    {"UMUtils", "isDeviceJailBreak"},
    {"UMUtils", "isAppPirate"},
};

#pragma mark - Video ad context + speed-up

static id webAdContext(WKWebView *web) {
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive ||
        !web.window || web.window.hidden ||
        (web.window.windowScene && web.window.windowScene.activationState != UISceneActivationStateForegroundActive) ||
        !ASPViewVisibleInSurface(web, web.window)) return @NO;
    BOOL exposed = NO;
    for (NSUInteger x = 1; x <= 3 && !exposed; x++) {
        for (NSUInteger y = 1; y <= 3; y++) {
            CGPoint point = [web convertPoint:CGPointMake(web.bounds.size.width * x / 4,
                web.bounds.size.height * y / 4) toView:web.window];
            UIView *hit = [web.window hitTest:point withEvent:nil];
            if (hit == web || [hit isDescendantOfView:web]) { exposed = YES; break; }
        }
    }
    if (!exposed) return @NO;
    NSInteger context = ASPManualSkipWebViewContext(web);
    if (context < 0) return @NO;
    return context > 0 ? @YES : NSNull.null;
}

static void setWebContext(WKWebView *web, WKFrameInfo *frame) {
    id active = webAdContext(web);
    [web callAsyncJavaScript:@"if (window.__adspeed && window.__adspeed.setAdContext) window.__adspeed.setAdContext(active);"
        arguments:@{@"active": active} inFrame:frame inContentWorld:WKContentWorld.pageWorld completionHandler:nil];
}

@interface ASPContextHandler : NSObject <WKScriptMessageHandler>
@end
@implementation ASPContextHandler
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    if (message.webView && message.frameInfo.mainFrame) setWebContext(message.webView, nil);
}
@end

static NSString *contextHandlerName(void) {
    static NSString *name;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ name = [@"AdVanishContext_" stringByAppendingString:NSUUID.UUID.UUIDString]; });
    return name;
}

static void refreshAdContexts(void);
static void scheduleAdPoll(void);

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (gActive) {
        ASPManualSkipTrackController(self);
        ASPAdCompletionTrackController(self);
        refreshAdContexts();
        scheduleAdPoll();
    }
}

%end

%hook AVPlayer
- (void)setRate:(float)rate {
    if (gActive && gAutomaticAds && !ASPSpeedInternalChange() && gSpeedVideo && isfinite(rate) && rate > 0) {
        ASPAdSurface *surface = ASPManualSkipSurfaceForPlayer(self, !gSpeedNative);
        if (surface) {
            ASPSpeedPrepareRate(self);
            float accelerated = fminf(rate * ASPSpeedRate(), ASPSpeedRate());
            %orig(accelerated);
            ASPSpeedTrackRate(self, surface.root, rate, accelerated);
            return;
        }
    }
    %orig(rate);
}
%end

static BOOL preventExternalURL(NSURL *url) {
    if (!gActive || !gBlockRedirects || !ASPManualSkipAdSurfaces().count) return NO;
    NSString *scheme = url.scheme.lowercaseString;
    return [@[@"http", @"https", @"itms-apps", @"itms-appss", @"itms-services"] containsObject:scheme];
}

%hook UIApplication
- (BOOL)openURL:(NSURL *)url {
    if (preventExternalURL(url)) return NO;
    return %orig;
}
- (void)openURL:(NSURL *)url options:(NSDictionary *)options completionHandler:(void (^)(BOOL))completion {
    if (preventExternalURL(url)) {
        if (completion) completion(NO);
        return;
    }
    %orig;
}
%end

#pragma mark - Shared WebKit media engine

static NSString *webSpeedJS(void) {
    static NSString *channel;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ channel = [[NSUUID UUID] UUIDString]; });
    NSDictionary *config = @{
        @"rate": @(ASPSpeedRate()),
        @"automatic": @(gAutomaticAds),
        @"speedVideo": @(gSpeedVideo),
        @"compressTimers": @(gWebTimers),
        @"accelerateClock": @(gWebClock),
        @"forceInline": @(gForceInline),
        @"recognizedAd": @NO,
        @"autoComplete": @(gAutoInteract && gAutomaticAds),
        @"preventRedirects": @(gBlockRedirects),
                @"skipChannel": channel,
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:config options:0 error:nil];
    if (!data) return nil;
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSString *script = [[NSString stringWithUTF8String:kAdSpeedWebScript]
        stringByReplacingOccurrencesOfString:@"__ADSPEED_CONFIG__" withString:json];
    return [@"/* AdSpeed shared media engine */\n" stringByAppendingString:script];
}

static BOOL webEnabled(void) {
    return gActive && (gManualSkip || gSpeedVideo || gWebTimers || gWebClock || gAutoInteract || gBlockRedirects);
}

static void installWebScript(WKWebViewConfiguration *configuration) {
    if (!webEnabled() || !configuration) return;
    WKUserContentController *controller = configuration.userContentController;
    for (WKUserScript *existing in controller.userScripts) {
        if ([existing.source hasPrefix:@"/* AdSpeed shared media engine */"]) return;
    }
    NSString *source = webSpeedJS();
    if (!source) return;
    WKUserScript *script = [[WKUserScript alloc] initWithSource:source
                                              injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                           forMainFrameOnly:NO];
    [controller addUserScript:script];
    NSString *handlerName = contextHandlerName();
    [controller addScriptMessageHandler:[ASPContextHandler new] name:handlerName];
    NSString *request = [NSString stringWithFormat:
        @"try { window.webkit.messageHandlers['%@'].postMessage(null); } catch (_) {}", handlerName];
    WKUserScript *contextRequest = [[WKUserScript alloc]
        initWithSource:request
        injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];
    [controller addUserScript:contextRequest];
}

%hook WKWebView
- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    if (webEnabled() && gForceInline && gSpeedVideo && configuration) {
        configuration.allowsInlineMediaPlayback = YES;
        configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    }
    installWebScript(configuration);
    return %orig;
}
- (instancetype)initWithCoder:(NSCoder *)coder {
    WKWebView *view = %orig;
    installWebScript(view.configuration);
    return view;
}
- (void)didMoveToWindow {
    %orig;
    if (webEnabled() && !self.window) setWebContext(self, nil);
    if (webEnabled() && self.window) {
        ASPManualSkipTrackWebView(self);
        if (!gWebViews) gWebViews = [NSHashTable weakObjectsHashTable];
        if (gWebViews.count >= 128) [gWebViews removeObject:gWebViews.allObjects.firstObject];
        [gWebViews addObject:self];
        installWebScript(self.configuration);
        NSString *source = webSpeedJS();
        if (source) [self evaluateJavaScript:source completionHandler:nil];
        refreshAdContexts();
        scheduleAdPoll();
    }
}
%end

#pragma mark - Bootstrap

static BOOL resolveActive(NSDictionary *prefs) {
#ifdef ADSPEED_FORCE_ON
    return YES; // standalone / TrollFools build: always on, ignore prefs
#else
    if (!prefBool(prefs, kKeyMaster, YES)) return NO;
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    NSString *appKey = [kKeyAppPrefix stringByAppendingString:bid];
    return prefBool(prefs, appKey, NO); // default OFF until enabled in Settings
#endif
}

// Which hook tables to (re)install. Ad SDKs load their frameworks lazily after
// launch, so hooking only once at %ctor misses them — we re-install whenever a new
// image is loaded.
static BOOL gInstallJB = NO;

static void installEnabled(void) {
    if (gInstallJB) {
        for (const AdHook &hook : kJailbreakHooks) installHook(&hook);
    }
    ASPAdCompletionInstallHooks();
}

static void refreshAdContexts(void) {
    if (!gActive || ![NSThread isMainThread]) return;
    ASPAdCompletionTrackController(nil);
    NSArray<ASPAdSurface *> *surfaces = ASPManualSkipAdSurfaces();
    for (WKWebView *web in gWebViews.allObjects) setWebContext(web, nil);
    for (ASPAdSurface *surface in surfaces) {
        ASPAdCompletionTrackController(surface.owner);
        if (gAutomaticAds && gSpeedVideo) {
            for (AVPlayer *player in surface.players) ASPSpeedAcceleratePlayer(player, surface.root);
        }
    }
}

static void scheduleAdPoll(void) {
    if (!gActive || gPollScheduled || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    BOOL hasSurface = ASPManualSkipAdSurfaces().count != 0;
    if (!hasSurface) {
        for (WKWebView *web in gWebViews.allObjects) {
            if (web.window && !web.window.hidden) {
                hasSurface = YES;
                break;
            }
        }
    }
    if (!hasSurface) return;
    gPollScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
        gPollScheduled = NO;
        refreshAdContexts();
        scheduleAdPoll();
    });
}

// Coalesce bursts of image loads into a single install on the main queue (never hook
// from inside the dyld callback itself — its lock may be held).
static void scheduleInstall(void) {
    static std::atomic<bool> pending(false);
    if (pending.exchange(true)) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        pending.store(false);
        installEnabled();
    });
}

static void imageAdded(const struct mach_header *mh, intptr_t slide) {
    scheduleInstall();
}

%ctor {
    @autoreleasepool {
#ifdef ADSPEED_JAILED
        if ([[NSBundle mainBundle].bundlePath.pathExtension isEqualToString:@"appex"]) return;
        NSString *configPath = [NSBundle.mainBundle pathForResource:@"AdVanish" ofType:@"plist"];
        NSDictionary *embedded = configPath ? [NSDictionary dictionaryWithContentsOfFile:configPath] : nil;
        NSMutableDictionary *prefs = [embedded isKindOfClass:NSDictionary.class] ?
            [embedded mutableCopy] : [NSMutableDictionary dictionary];
        NSDictionary *stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:@"AdVanish"];
        if (stored) [prefs addEntriesFromDictionary:stored];
        gActive = prefBool(prefs, @"Enabled", YES);
        if (!gActive) return;
        gSpeedVideo = prefBool(prefs, @"SpeedUpVideo", YES);
        gWebTimers = prefBool(prefs, @"CompressTimers", YES);
        gWebClock = prefBool(prefs, @"AccelerateClock", YES);
        gForceInline = prefBool(prefs, @"ForceInline", NO);
        gManualSkip = prefBool(prefs, @"ManualSkip", YES);
        gAutomaticAds = automaticAdsPreference(prefs, @"AutomaticAds", @"ManualSkip");
        gSpeedNative = prefBool(prefs, @"SpeedNativeVideo", NO);
        gAutoInteract = prefBool(prefs, @"AutoInteract", YES);
        gAutoDismiss = prefBool(prefs, @"AutoDismiss", YES);
        gBlockRedirects = prefBool(prefs, @"BlockRedirects", YES);
#else
        NSDictionary *prefs = loadPrefs();
        gActive = resolveActive(prefs);

        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
#ifdef ADSPEED_DEBUG
        aspLog(@"==== AdSpeed loaded in %@ ====", bid);
        aspLog(@"prefs file found: %@", prefs ? @"YES" : @"NO");
        aspLog(@"master=%d  appEnabled(%@)=%d  -> active=%d",
               prefBool(prefs, kKeyMaster, YES),
               bid, prefBool(prefs, [kKeyAppPrefix stringByAppendingString:bid], NO),
               gActive);
#endif
#ifdef ADSPEED_DUMP
        // opt-in only; objc_copyClassList crashes some apps even when deferred
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ aspDumpAdClasses(); });
#endif

        if (!gActive) return;

        // Per-app settings, keyed by this app's bundle id (resolved above).
        gManualSkip = prefBool(prefs, appKey(bid, kKeyManualSkip), YES);
        gAutomaticAds = automaticAdsPreference(prefs, appKey(bid, @"AutomaticAds"), appKey(bid, kKeyManualSkip));
        gSpeedVideo  = prefBool(prefs, appKey(bid, kKeySpeedVideo), YES);
        gWebTimers   = prefBool(prefs, appKey(bid, kKeyWebTimers), YES);
        gWebClock    = prefBool(prefs, appKey(bid, kKeyWebClock), YES);
        gForceInline = prefBool(prefs, appKey(bid, kKeyForceInline), NO);
        gSpeedNative = prefBool(prefs, appKey(bid, kKeySpeedNative), NO);
        gAutoInteract = prefBool(prefs, appKey(bid, @"AutoInteract"), YES);
        gAutoDismiss = prefBool(prefs, appKey(bid, @"AutoDismiss"), YES);
        gBlockRedirects = prefBool(prefs, appKey(bid, @"BlockRedirects"), YES);
        gInstallJB  = prefBool(prefs, appKey(bid, kKeyBypassJB), YES);
#endif
        ASPManualSkipConfigure(gManualSkip);
        ASPAdCompletionConfigure(gAutoDismiss && gAutomaticAds);
        installEnabled();
        _dyld_register_func_for_add_image(&imageAdded);
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
                refreshAdContexts();
                scheduleAdPoll();
            }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
                refreshAdContexts();
            }];
        // Single ungrouped %init reached by both builds — installs the AVPlayer + WKWebView
        // hooks, which self-gate on the flags above.
        %init;
    }
}
