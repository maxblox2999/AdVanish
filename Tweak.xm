// Ads Speed - rewritten 2.1
//
// Two ways to ship this:
//   1) As a .deb  -> injected into every UIKit app via the filter (adspeed.plist),
//                    then gated at runtime per-app from the Settings panel.
//   2) Statically injected into a single .ipa (e.g. TrollFools). For that build,
//      compile with -DADSPEED_FORCE_ON so it is always active and ignores prefs.
//
// Manual skipping uses AVPlayer and HTML video interfaces inside enabled apps.
// It does not depend on an ad SDK's class names. The older SDK blocking and
// context-based acceleration remain separate options.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <mach-o/dyld.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <math.h>
#include <atomic>
#import "ASPUniversalSkip.h"
#import "ASPManualSkip.h"
#include "AdSpeedWebScript.h"

#pragma mark - Preferences

static NSString *const kKeyMaster     = @"Enabled";        // master on/off, default YES
static NSString *const kKeyBlockAds   = @"BlockAds";       // SDK ad blocking, default YES
static NSString *const kKeySpeedVideo = @"SpeedUpVideo";   // speed up ad video, default YES
static NSString *const kKeyVideoRate  = @"VideoRate";      // playback multiplier, default 8.0
static NSString *const kKeyWebTimers  = @"CompressTimers"; // compress JS setTimeout/setInterval, default NO
static NSString *const kKeyWebClock   = @"AccelerateClock"; // also run Date.now/performance.now fast, default NO
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
static float gVideoRate  = 8.0f;

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

static float prefRate(id value) {
    float rate = [value respondsToSelector:@selector(floatValue)] ? [value floatValue] : 8.0f;
    if (!isfinite(rate)) return 8.0f;
    return fmaxf(1.0f, fminf(rate, 16.0f));
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

#pragma mark - Typed stubs

// NO / nil / 0 are bit-identical in x0 on arm64, but naming the intent keeps the
// hook table readable and avoids surprises if this is ever ported.
static BOOL returnFalse(__unused id self, __unused SEL _cmd) { return NO; }
static id   returnNil  (__unused id self, __unused SEL _cmd) { return nil; }
static void returnVoid (__unused id self, __unused SEL _cmd) { }

typedef enum { StubBOOL, StubNil, StubVoid } StubType;
typedef struct { const char *cls; const char *sel; StubType type; } AdHook;

static IMP stubFor(StubType t) {
    return (t == StubNil)  ? (IMP)returnNil
         : (t == StubVoid) ? (IMP)returnVoid
                           : (IMP)returnFalse;
}

static void installResolvedHook(Class target, SEL selector, IMP replacement) {
    static NSMutableSet<NSString *> *installed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ installed = [NSMutableSet set]; });
    NSString *key = [NSString stringWithFormat:@"%p:%s", (__bridge void *)target, sel_getName(selector)];
    if ([installed containsObject:key]) return;
    MSHookMessageEx(target, selector, replacement, NULL);
    [installed addObject:key];
}

static void installHook(const AdHook *h) {
    Class c = objc_getClass(h->cls);
    if (!c) return;
    SEL s = sel_registerName(h->sel);
    // Only retarget a method the class actually implements - never add new methods,
    // which would alter -respondsToSelector: behaviour.
    if (!class_getInstanceMethod(c, s)) return;
    installResolvedHook(c, s, stubFor(h->type));
}

// Same, but for class methods (e.g. +[IronSource hasRewardedVideo]): hook the metaclass.
static void installClassHook(const AdHook *h) {
    Class c = objc_getClass(h->cls);
    if (!c) return;
    SEL s = sel_registerName(h->sel);
    if (!class_getClassMethod(c, s)) return;
    installResolvedHook(object_getClass(c), s, stubFor(h->type));
}

static void installAll(const AdHook *table, size_t n) {
    for (size_t i = 0; i < n; i++) installHook(&table[i]);
}

static void installAllClass(const AdHook *table, size_t n) {
    for (size_t i = 0; i < n; i++) installClassHook(&table[i]);
}

#pragma mark - Ad-SDK blocking table

static const AdHook kAdHooks[] = {
    // Generic / app-specific ad managers
    {"GADAdSource", "invalidated", StubBOOL},
    {"ALMediationServiceAdDelegateProxy", "didLoadAd:withExtraInfo:", StubVoid},
    {"AdsHandler", "pauseAll:", StubVoid},
    {"AdsHandler", "clear", StubVoid},
    {"AdsHandler", "setPossibleAdsPerHour:", StubVoid},
    {"AdsHandler", "init", StubNil},
    {"AdsHandler", "clearTimeSinceLiveStarted", StubVoid},
    {"AdsHandler", "updateTimeSinceLiveStarted", StubVoid},
    {"BasePlayerView", "OnPlayer_AdStarted:", StubVoid},
    {"FullScreenViewTVAIS", "getLastPlayedChannel", StubNil},
    {"FullScreenViewTVAIS", "startPlayChannel:forceStart:", StubVoid},
    {"RFQVideoPlayer", "checkIsPreviewEnded", StubBOOL},
    {"RFQVideoPlayerAd", "onAdStartedPlay", StubVoid},
    {"RFQVideoPlayerAd", "adShouldStartPlay", StubBOOL},
    {"RFQVideoPlayerAd", "setAdShouldStartPlay:", StubVoid},
    {"RSVodHead", "isPreview", StubBOOL},
    {"RSVodHead", "isPreviewEnded", StubBOOL},
    {"RSVodHead", "setIsPreview:", StubVoid},
    {"RSVodHead", "setIsPreviewEnded:", StubVoid},
    {"TAGPreviewManager", "isPreviewingContainer:", StubBOOL},
    {"TabBarBaseVC", "OnHeadLoadSuccess", StubVoid},
    {"UMPConsentInformation", "canRequestAds", StubBOOL},
    {"XmppVCardInfo", "hasAnyAds", StubBOOL},
    {"XmppVCardInfo", "hasNativeAds", StubBOOL},
    {"XmppVCardInfo", "hasRegularAds", StubBOOL},

    // Snap ad cache / serve
    {"SCSnapAdsAdResponsePersistentCache", "_getAdResponse:removeAdResponseOnHit:", StubNil},
    {"SCSnapAdsAdSourceConfig", "shouldDisableServeRequest", StubBOOL},
    {"SCSnapAdsAdSourceConfig", "protoServeEndpoint", StubNil},
    {"SCSnapAdsAdSourceConfig", "protoInitEndpoint", StubNil},
    {"SCSnapAdsDynamicAdMediaManagerImpl", "removeMediaDataSource:", StubVoid},
    {"SCSnapAdsOnDeviceInfoRecordCoordinator", "_handleRemoveOnDeviceInfoRecordsWithSuccess:completionBlock:", StubVoid},
    {"SCSnapAdsOnDeviceInfoRecordCoordinator", "removeAllOnDeviceInfoRecordsForSaid:completionQueue:completionBlock:", StubVoid},
    {"SCSnapAdsServeResponseDataStore", "_removeAdResponseForIdentifier:", StubVoid},
    {"SCSnapAdsServeResponseDataStore", "removeAdResponseForIdentifier:", StubVoid},

    // Vungle
    {"VungleURLConfiguration", "setAdsURL:", StubVoid},

    // Mintegral (MTG*) — selectors verified against the AppLovin↔Mintegral adapter.
    // Old interstitial-video + rewarded managers (this is what Tycoon Empire uses):
    {"MTGInterstitialVideoAdManager", "isVideoReadyToPlayWithPlacementId:unitId:", StubBOOL},
    {"MTGBidInterstitialVideoAdManager", "isVideoReadyToPlayWithPlacementId:unitId:", StubBOOL},
    {"MTGRewardAdManager", "isVideoReadyToPlayWithPlacementId:unitId:", StubBOOL},
    {"MTGBidRewardAdManager", "isVideoReadyToPlayWithPlacementId:unitId:", StubBOOL},
    // New interstitial managers use -isAdReady:
    {"MTGNewInterstitialAdManager", "isAdReady", StubBOOL},
    {"MTGNewInterstitialBidAdManager", "isAdReady", StubBOOL},
    // Splash / app-open:
    {"MTGSplashAD", "isBiddingADReadyToShow", StubBOOL},

    // Misc
    {"FPUserCredentials", "adremoval_enabled", StubBOOL},

    // AppLovin (AL* / MA*)
    {"ALIncentivizedInterstitialAd", "isReadyForDisplay", StubBOOL},
    {"ALMediatedAd", "isReady", StubBOOL},
    {"ALStoreKitProductViewController", "isReady", StubBOOL},
    {"ALStoreProductViewControllerWrapper", "isReady", StubBOOL},
    {"ALDCreativeDebuggerTableViewDataSource", "initializeWithDisplayedAds:", StubVoid},
    {"ALMediationAdLoadCoordinator", "didLoadAd:", StubVoid},
    {"ALMediationSetting", "fullscreenAdShouldReturnReadyWhenAdLoadIsInProgress", StubBOOL},
    {"ALAdLoadState", "isWaitingForAd", StubBOOL},
    {"ALAdLoadState", "setIsWaitingForAd:", StubVoid},
    {"ALAdService", "hasPreloadedAdOfSize:", StubBOOL},
    {"ALAdService", "hasPreloadedAdForZoneIdentifier:", StubBOOL},
    {"ALFullScreenAdTracker", "isFullScreenAdShowing", StubBOOL},
    {"ALMediationAdLoadState", "isWaitingForAd", StubBOOL},
    {"ALMediationAdLoadState", "setIsWaitingForAd:", StubVoid},
    {"ALMediationAdapterRouter", "isAdShowingForAdapter:", StubBOOL},
    {"ALNativeAdService", "loadNextAdAndNotify:", StubVoid},
    {"MAAd", "isReady", StubBOOL},
    {"MAAppOpenAd", "isReady", StubBOOL},
    {"MAFullscreenAdController", "isReady", StubBOOL},
    {"MAInterstitialAd", "isReady", StubBOOL},
    {"MARewardedAd", "isReady", StubBOOL},
    {"MARewardedInterstitialAd", "isReady", StubBOOL},
    {"MANativeAdSource", "isAdLoading", StubBOOL},

    // Meta Audience Network
    {"FBAdDSLBridgeViewController", "isReadyToPresent", StubBOOL},

    // Google IMA
    {"IMAAd", "isSkippable", StubBOOL},
    {"IMAAd", "isUiDisabled", StubBOOL},

    // ironSource (IS*)
    {"ISAdMobBannerAdapter", "isLargeScreen", StubBOOL},
    {"ISBaseAdUnitInteractionSmash", "isReadyToShow", StubBOOL},
    {"ISBaseAdUnitManager", "isReadyToShow", StubBOOL},
    {"ISBaseAdUnitSmash", "isReadyToShow", StubBOOL},
    {"ISDemandOnlyIsSmash", "isReadyToShow", StubBOOL},
    {"ISDemandOnlyRvSmash", "isReadyToShow", StubBOOL},
    {"ISLWSProgRvSmash", "isReadyToShow", StubBOOL},
    {"ISProgIsSmash", "isReadyToShow", StubBOOL},

    // Google AdMob (GAD*)
    {"GADView", "initWithFrame:context:", StubNil},
    {"GADBannerAd", "adView", StubNil},
    {"GADBannerAd", "videoController", StubNil},
    {"GADCustomEventBannerAdRenderer", "renderWithServerTransaction:adConfiguration:completionHandler:", StubVoid},
    {"GADFullScreenAdViewController", "viewWillAppear:", StubVoid},
    {"GADFullScreenAdViewController", "presented", StubBOOL},
    {"GADFullScreenAdViewController", "canPresentFromViewController:error:", StubBOOL},
    {"GADInlineInterstitialAdRenderer", "renderWithServerTransaction:adConfiguration:completionHandler:", StubVoid},
    {"GADInlineMultipleNativeAdsRenderer", "renderWithServerTransaction:adConfiguration:completionHandler:", StubVoid},
    {"GADInlineMultipleNativeAdsRenderer", "init", StubNil},
    {"GADMediationBannerAdRenderer", "renderWithServerTransaction:adConfiguration:completionHandler:", StubVoid},
    {"GADMediationBannerAdRenderer", "adapter:didReceiveAdView:", StubVoid},
    {"GADRTBMediationBannerAdRenderer", "renderWithServerTransaction:adConfiguration:completionHandler:", StubVoid},
    {"GADUnifiedMediationBannerAdRenderer", "renderWithServerTransaction:adConfiguration:completionHandler:", StubVoid},
    {"GADInlineBannerAdRenderer", "renderWithServerTransaction:adConfiguration:completionHandler:", StubVoid},
    {"GADAdRenderResult", "rendererClassString", StubNil},
    {"GADAdRenderResult", "setRendererClassString:", StubVoid},
    {"GADInlineSingleNativeAdRenderer", "init", StubNil},
    {"GADInternalBannerView", "callBackAdViewDidReceiveAd", StubVoid},
    {"GADMediatedAdRenderer", "adapter:didReceiveAdView:", StubVoid},
    {"GADBannerView", "bannerViewDidReceiveAd:", StubVoid},
    {"GADBannerView", "bannerView:didFailToReceiveAdWithError:", StubVoid},
    {"GADBannerView", "bannerViewDidRecordImpression:", StubVoid},
    {"GADBannerView", "bannerViewWillPresentScreen:", StubVoid},
    {"GADBannerView", "adViewIntrinsicContentSizeDidChange:", StubVoid},
    {"GADBannerView", "setAutoloadEnabled:", StubVoid},
    {"GADBannerView", "setAdUnitID:", StubVoid},
    {"GADBannerView", "loadRequest:", StubVoid},

    // OMID (Open Measurement) ad sessions
    {"GADOMIDAdSessionRegistry", "isActive", StubBOOL},
    {"GADOMIDAdSessionRegistry", "removeAdSession:", StubVoid},
    {"GADOMIDAdSessionRegistry", "adSessions", StubNil},
    {"GADOMIDAdSessionRegistry", "activeAdSessions", StubNil},
    {"GADOMIDAdSessionRegistry", "addAdSession:", StubVoid},
    {"GADMinimumVersionSupport", "OSIsSupported", StubBOOL},

    // React Native Google Mobile Ads
    {"RNGoogleMobileAdsBannerComponent", "didSetProps:", StubVoid},
    {"RNGoogleMobileAdsBannerComponent", "banner", StubNil},
    {"RNGoogleMobileAdsBannerComponent", "requested", StubBOOL},
    {"RNGoogleMobileAdsBannerComponent", "setBanner:", StubVoid},
    {"RNGoogleMobileAdsBannerComponent", "request", StubVoid},
    {"RNGoogleMobileAdsBannerComponent", "propsChanged", StubBOOL},
    {"RNGoogleMobileAdsBannerComponent", "onNativeEvent", StubVoid},
    {"RNGoogleMobileAdsBannerComponent", "setPropsChanged:", StubVoid},
    {"RNGoogleMobileAdsBannerViewManager", "view", StubNil},
    {"RNGoogleMobileAdsBannerViewManager", "methodQueue", StubNil},
    {"RNGoogleMobileAdsBannerViewManager", "propConfig_unitId", StubNil},
    {"RNGoogleMobileAdsBannerViewManager", "propConfig_sizes", StubNil},
    {"RNGoogleMobileAdsBannerViewManager", "propConfig_onNativeEvent", StubNil},
    {"RNGoogleMobileAdsBannerViewManager", "propConfig_manualImpressionsEnabled", StubNil},
    {"RNGoogleMobileAdsBannerViewManager", "recordManualImpression:", StubVoid},
    {"RNGoogleMobileAdsBannerViewManager", "bridge", StubNil},
    {"RNGoogleMobileAdsBannerViewManager", "propConfig_request", StubNil},

    // App-specific banner
    {"_TtC9BusTaiwan20YBGoogleBannerAdView", "loadAd", StubVoid},

    // Personalised ads config
    {"APMPersistedConfig", "allowPersonalizedAds", StubBOOL},

    // ===================================================================
    // Current ad SDKs (2024-2026). Each entry neutralises a "ready / valid /
    // cached / can-present" check so the host app believes no ad is available.
    // Names are from public SDK APIs; versions vary, so misses are silent no-ops.
    // Swift-only SDKs (Unity Ads, new InMobiSDK.*, new GoogleMobileAds Swift)
    // can't be reached this way — see the web speed-up path for those.
    // ===================================================================

    // Meta Audience Network (FAN)
    {"FBInterstitialAd", "isAdValid", StubBOOL},
    {"FBRewardedVideoAd", "isAdValid", StubBOOL},
    {"FBRewardedInterstitialAd", "isAdValid", StubBOOL},
    {"FBNativeAd", "isAdValid", StubBOOL},

    // Google AdMob / Google Mobile Ads (ObjC GAD*) — block full-screen presentation
    {"GADInterstitialAd", "canPresentFromRootViewController:error:", StubBOOL},
    {"GADRewardedAd", "canPresentFromRootViewController:error:", StubBOOL},
    {"GADRewardedInterstitialAd", "canPresentFromRootViewController:error:", StubBOOL},
    {"GADAppOpenAd", "canPresentFromRootViewController:error:", StubBOOL},

    // ironSource LevelPlay (newer instance API; class API is in kAdClassHooks)
    {"LPMInterstitialAd", "isAdReady", StubBOOL},
    {"LPMRewardedAd", "isAdReady", StubBOOL},

    // Vungle / Liftoff Monetize
    {"VungleInterstitial", "canPlayAd", StubBOOL},
    {"VungleRewarded", "canPlayAd", StubBOOL},
    {"VungleInterstitialAd", "canPlayAd", StubBOOL},
    {"VungleRewardedAd", "canPlayAd", StubBOOL},
    {"VungleSDK", "isAdCachedForPlacementID:", StubBOOL},
    {"VungleSDK", "isAdCachedForPlacementID:adMarkup:", StubBOOL},

    // Chartboost
    {"CHBInterstitial", "isCached", StubBOOL},
    {"CHBRewarded", "isCached", StubBOOL},
    {"CHBBanner", "isCached", StubBOOL},

    // Tapjoy
    {"TJPlacement", "isContentReady", StubBOOL},
    {"TJPlacement", "isContentAvailable", StubBOOL},

    // Pangle (ByteDance). New PAG* API has no readiness flag — block the show call
    // (presentFromRootViewController:). Older "BU" SDK exposes a validity flag.
    {"PAGLInterstitialAd", "presentFromRootViewController:", StubVoid},
    {"PAGRewardedAd", "presentFromRootViewController:", StubVoid},
    {"PAGAppOpenAd", "presentFromRootViewController:", StubVoid},
    {"BUFullscreenVideoAd", "isAdValid", StubBOOL},
    {"BURewardedVideoAd", "isAdValid", StubBOOL},
    {"BUNativeExpressFullscreenVideoAd", "isAdValid", StubBOOL},

    // InMobi (older ObjC SDK; the new InMobiSDK.* is Swift and not reachable here)
    {"IMInterstitial", "isReady", StubBOOL},

    // AdColony (legacy, still embedded via DT mediation)
    {"AdColonyInterstitial", "expired", StubBOOL},

    // Smaato
    {"SMAInterstitial", "isAvailableForPresentation", StubBOOL},
    {"SMARewardedInterstitial", "isAvailableForPresentation", StubBOOL},

    // Yandex Mobile Ads (RU) — block the loaded ad presentation gate where present
    {"YMAInterstitialAd", "isLoaded", StubBOOL},
    {"YMARewardedAd", "isLoaded", StubBOOL},

    // Bigo Ads
    {"BigoInterstitialAd", "isExpired", StubBOOL},
    {"BigoRewardVideoAd", "isExpired", StubBOOL},
};

// Class-method "is ready" checks (hook the metaclass).
static const AdHook kAdClassHooks[] = {
    // ironSource classic (mediation + DemandOnly) — all class methods returning BOOL
    {"IronSource", "hasRewardedVideo", StubBOOL},
    {"IronSource", "hasInterstitial", StubBOOL},
    {"IronSource", "hasISDemandOnlyInterstitial:", StubBOOL},
    {"IronSource", "hasISDemandOnlyRewardedVideo:", StubBOOL},

    // Digital Turbine FairBid (formerly Fyber) — class-method availability checks
    {"FYBInterstitial", "isAvailable:", StubBOOL},
    {"FYBRewarded", "isAvailable:", StubBOOL},
};

#pragma mark - Jailbreak-detection bypass table

static const AdHook kJailbreakHooks[] = {
    {"BUDeviceHelper", "bu_isJailBroken", StubBOOL},
    {"EBAppLogDeviceHelper", "isJailBroken", StubBOOL},
    {"HMDBUInfo", "isJailBroken", StubBOOL},
    {"MobClick", "isJailbroken", StubBOOL},
    {"MobClick", "isPirated", StubBOOL},
    {"SSEDeviceStatus", "jailBroken", StubBOOL},
    {"UMUtils", "isDeviceJailBreak", StubBOOL},
    {"UMUtils", "isAppPirate", StubBOOL},
};

#pragma mark - Video ad context + speed-up

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (gActive) ASPManualSkipTrackController(self);
}
%end

// Only touch playback rate while an ad is on screen; leave the app's own video alone.
%hook AVPlayer
- (void)setRate:(float)rate {
#ifdef ADSPEED_DEBUG
    if (gActive && rate > 0.0f) aspLog(@"AVPlayer setRate %.2f", rate);
#endif
    // Legacy acceleration uses a visible owner and its actual player. The
    // explicit all-native preference still permits other players.
    if (gActive && !gManualSkip && gSpeedVideo && isfinite(rate) && rate > 0.0f &&
        (gSpeedNative || ASPManualSkipIsAdPlayer(self))) {
        %orig(fminf(rate * gVideoRate, 16.0f));
    } else {
        %orig(rate);
    }
}
%end

#pragma mark - Shared WebKit media engine

static NSString *webSpeedJS(void) {
    static NSString *channel;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ channel = [[NSUUID UUID] UUIDString]; });
    NSDictionary *config = @{
        @"rate": @(gVideoRate),
        @"speedVideo": @(gSpeedVideo),
        @"compressTimers": @(gWebTimers),
        @"accelerateClock": @(gWebClock),
        @"forceInline": @(gForceInline),
        @"autoSkip": @NO,
        @"manualPlayback": @YES,
        @"manualClose": @(gManualSkip),
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
    return gActive && (gManualSkip || gSpeedVideo || gWebTimers || gWebClock);
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
    if (webEnabled() && self.window) {
        if (gManualSkip) ASPManualSkipTrackWebView(self);
        installWebScript(self.configuration);
        NSString *source = webSpeedJS();
        if (source) [self evaluateJavaScript:source completionHandler:nil];
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
static BOOL gInstallAds = NO;
static BOOL gInstallJB  = NO;

static void installEnabled(void) {
    if (gInstallAds) {
        installAll(kAdHooks, sizeof(kAdHooks) / sizeof(kAdHooks[0]));
        installAllClass(kAdClassHooks, sizeof(kAdClassHooks) / sizeof(kAdClassHooks[0]));
    }
    if (gInstallJB)  installAll(kJailbreakHooks, sizeof(kJailbreakHooks) / sizeof(kJailbreakHooks[0]));
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
        // Jailed / sideload build: inject this dylib into an .ipa (TrollStore + TrollFools
        // or Sideloadly with its "Cydia Substrate" option, which supply the substrate the
        // hooks need). No package manager, Settings panel or prefs on a non-jailbroken
        // device, so hard-code the safe subset: always on, webview <video> speed-up only —
        // no native AVPlayer (would also hit in-game cutscenes you couldn't turn off),
        // no timer/clock tricks, no ad blocking.
        #ifndef ADSPEED_JAILED_RATE
        #define ADSPEED_JAILED_RATE 8.0f
        #endif
        gActive = YES;
        gSpeedVideo = YES;
        gSpeedNative = NO; gWebTimers = NO; gWebClock = NO;
        gVideoRate = prefRate(@(ADSPEED_JAILED_RATE));
        // falls through to the single %init below (logos counts %init across the whole
        // file ignoring #ifdef, so there must be exactly one in the source).
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
        gSpeedVideo  = !gManualSkip && prefBool(prefs, appKey(bid, kKeySpeedVideo), YES);
        gWebTimers   = !gManualSkip && prefBool(prefs, appKey(bid, kKeyWebTimers), NO);
        gWebClock    = !gManualSkip && prefBool(prefs, appKey(bid, kKeyWebClock), NO);
        gForceInline = !gManualSkip && prefBool(prefs, appKey(bid, kKeyForceInline), NO);
        gSpeedNative = prefBool(prefs, appKey(bid, kKeySpeedNative), NO);
        id rateVal = prefs[appKey(bid, kKeyVideoRate)];
        gVideoRate = prefRate(rateVal);

        // Blocking readiness prevents the media path from starting at all.
        gInstallAds = !gManualSkip && prefBool(prefs, appKey(bid, kKeyBlockAds), NO);
        gInstallJB  = prefBool(prefs, appKey(bid, kKeyBypassJB), YES);
        ASPManualSkipConfigure(gManualSkip);

        installEnabled();                              // classes already loaded
        _dyld_register_func_for_add_image(&imageAdded); // + lazily-loaded ad SDKs

#endif
        // Single ungrouped %init reached by both builds — installs the AVPlayer + WKWebView
        // hooks, which self-gate on the flags above.
        %init;
    }
}
