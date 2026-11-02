// Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <cstring>
#import <mach-o/dyld.h>
#include <cmath>
#import "ASPPaths.h"
#import "ASPStorePolicy.h"
#import <StoreKit/StoreKit.h>
#import "ASPManualSkip.h"
#import "ASPSpeed.h"
#import "ASPAdCompletion.h"
#include "AdSpeedWebScript.h"
#import "ASPTimers.h"
#import "AVNRuntime.h"

@interface AVNOptions : NSObject
@property (nonatomic) BOOL enabled;
@property (nonatomic) BOOL automatic;
@property (nonatomic) BOOL button;
@property (nonatomic) BOOL video;
@property (nonatomic) BOOL timers;
@property (nonatomic) BOOL clocks;
@property (nonatomic) BOOL interaction;
@property (nonatomic) BOOL dismissal;
@property (nonatomic) BOOL redirects;
@property (nonatomic) BOOL hideStore;
@property (nonatomic) BOOL blockBanners;
@property (nonatomic) BOOL inlineVideo;
+ (instancetype)readConfiguration;
@end

@implementation AVNOptions
+ (instancetype)readConfiguration {
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"";
#ifdef ADSPEED_JAILED
    NSString *file = [NSBundle.mainBundle pathForResource:@"AdVanish" ofType:@"plist"];
    if (file) [values addEntriesFromDictionary:[NSDictionary dictionaryWithContentsOfFile:file] ?: @{}];
    [values addEntriesFromDictionary:[NSUserDefaults.standardUserDefaults dictionaryForKey:@"AdVanish"] ?: @{}];
#else
    NSDictionary *stored = ASPReadPreferencesAtPaths(ASPPrefsPaths(@"com.34306-sr.adspeed"));
    [values addEntriesFromDictionary:ASPApplicationPreferences(stored, bundle)];
#endif
    BOOL (^flag)(NSString *, BOOL) = ^BOOL(NSString *key, BOOL fallback) {
        return ASPPreferenceFlag(values, key, fallback);
    };
    AVNOptions *options = [AVNOptions new];
    options.enabled = flag(@"Enabled", YES);
#ifndef ADSPEED_JAILED
#ifndef ADSPEED_FORCE_ON
    options.enabled = options.enabled && flag(@"AppEnabled", NO);
#endif
#endif
    options.button = flag(@"ManualSkip", YES);
    options.automatic = ASPAutomaticAdsEnabled(values);
    options.video = flag(@"SpeedUpVideo", YES);
    options.timers = flag(@"CompressTimers", YES);
    options.clocks = flag(@"AccelerateClock", YES);
    options.interaction = flag(@"AutoInteract", YES);
    options.dismissal = flag(@"AutoDismiss", YES);
    options.redirects = flag(@"BlockRedirects", YES);
    options.hideStore = flag(@"HideAppStore", YES);
    options.blockBanners = flag(@"BlockBanners", NO);
    options.inlineVideo = flag(@"ForceInline", NO);
    if (!ASPApplicationHost(bundle, NSBundle.mainBundle.bundlePath)) options.enabled = NO;
    return options;
}
@end

@interface AVNRuntime : NSObject <WKScriptMessageHandler>
@property (nonatomic, strong) AVNOptions *options;
@property (nonatomic, strong) NSHashTable<WKWebView *> *pages;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, copy) NSString *messageName;
@property (nonatomic, strong) dispatch_source_t timer;
@property (nonatomic) BOOL refreshQueued;
+ (instancetype)shared;
- (void)begin;
- (void)requestAdapters;
- (void)refresh;
- (void)observe:(UIViewController *)controller;
- (void)mount:(WKWebView *)page;
- (void)prepare:(WKWebViewConfiguration *)configuration;
- (BOOL)blocks:(NSURL *)url;
@end

@implementation AVNRuntime
+ (instancetype)shared {
    static AVNRuntime *runtime;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        runtime = [AVNRuntime new];
        runtime.options = [AVNOptions readConfiguration];
        runtime.pages = [NSHashTable weakObjectsHashTable];
        runtime.messageName = [@"AVN_" stringByAppendingString:NSUUID.UUID.UUIDString];
        AVNOptions *o = runtime.options;
        NSDictionary *configuration = @{
            @"rate": @(ASPSpeedRate()), @"automatic": @(o.automatic), @"speedVideo": @(o.video),
            @"compatibilityPlayback": @YES,
            @"compressTimers": @(o.timers), @"accelerateClock": @(o.clocks),
            @"forceInline": @(o.inlineVideo), @"recognizedAd": @NO,
            @"autoComplete": @(o.interaction && o.automatic), @"autoDismiss": @(o.dismissal && o.automatic), @"preventRedirects": @(o.redirects),
            @"hideAppStore": @(o.hideStore),
            @"skipChannel": NSUUID.UUID.UUIDString
        };
        NSData *json = [NSJSONSerialization dataWithJSONObject:configuration options:0 error:nil];
        NSString *body = [[NSString stringWithUTF8String:kAdSpeedWebScript]
            stringByReplacingOccurrencesOfString:@"__ADSPEED_CONFIG__"
            withString:[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]];
        runtime.source = [@"/* AdVanish runtime v1 */\n" stringByAppendingString:body];
    });
    return runtime;
}
- (BOOL)blocks:(NSURL *)url {
    if (!self.options.enabled || !NSThread.isMainThread || !ASPManualSkipAdSurfaces().count) return NO;
    if (ASPAppStoreURL(url)) return self.options.hideStore;
    if (!self.options.redirects) return NO;
    NSString *scheme = url.scheme.lowercaseString;
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] ||
        [scheme hasPrefix:@"itms-"];
}
- (void)prepare:(WKWebViewConfiguration *)configuration {
    if (!self.options.enabled) return;
    WKUserContentController *content = configuration.userContentController;
    if (!content) return;
    for (WKUserScript *script in content.userScripts) {
        if ([script.source hasPrefix:@"/* AdVanish runtime v1 */"]) return;
    }
    [content addScriptMessageHandler:self name:self.messageName];
    [content addUserScript:[[WKUserScript alloc] initWithSource:self.source
        injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
    NSString *request = [NSString stringWithFormat:
        @"try {window.webkit.messageHandlers['%@'].postMessage(1)} catch (e) {}", self.messageName];
    [content addUserScript:[[WKUserScript alloc] initWithSource:request
        injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
}
- (void)authorize:(WKWebView *)page {
    BOOL visible = UIApplication.sharedApplication.applicationState == UIApplicationStateActive &&
        page.window && ASPViewVisibleInSurface(page, page.window) &&
        (!page.window.windowScene || page.window.windowScene.activationState == UISceneActivationStateForegroundActive);
    BOOL hit = NO;
    if (visible) {
        for (NSInteger sample = 0; sample < 9 && !hit; sample++) {
            CGPoint local = CGPointMake(page.bounds.size.width * (sample % 3 + 1) / 4.0,
                page.bounds.size.height * (sample / 3 + 1) / 4.0);
            UIView *target = [page.window hitTest:[page convertPoint:local toView:page.window] withEvent:nil];
            hit = target == page || [target isDescendantOfView:page];
        }
    }
    NSInteger context = visible && hit ? ASPManualSkipWebViewContext(page) : -1;
    id value = context < 0 ? @NO : context > 0 ? @YES : NSNull.null;
    [page callAsyncJavaScript:@"if(window.__adspeed) window.__adspeed.setAdContext(context)"
        arguments:@{@"context": value} inFrame:nil inContentWorld:WKContentWorld.pageWorld completionHandler:nil];
}
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    if (message.frameInfo.mainFrame && message.webView) [self authorize:message.webView];
}
- (void)mount:(WKWebView *)page {
    if (!self.options.enabled) return;
    if (!NSThread.isMainThread) return;
    if (page.window) {
        ASPManualSkipTrackWebView(page);
        if (self.pages.count == 128 && ![self.pages containsObject:page]) [self.pages removeObject:self.pages.allObjects.firstObject];
        [self.pages addObject:page];
        [self prepare:page.configuration];
        [page evaluateJavaScript:self.source completionHandler:nil];
    }
    [self authorize:page];
    if (!page.window) [self.pages removeObject:page];
    [self refresh];
}
- (void)observe:(UIViewController *)controller {
    if (!self.options.enabled) return;
    if ([controller.viewIfLoaded.window isKindOfClass:NSClassFromString(@"ASPSkipWindow")]) return;
    ASPManualSkipTrackController(controller);
    ASPAdCompletionTrackController(controller);
    [self refresh];
}
- (void)refresh {
    if (!NSThread.isMainThread) return;
    if (!self.options.enabled) { ASPTimerSetAdActive(NO); return; }
    ASPManualSkipRefresh();
    BOOL active = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    ASPAdCompletionTrackController(nil);
    NSArray<ASPAdSurface *> *surfaces = ASPManualSkipAdSurfaces();
    for (WKWebView *page in self.pages.allObjects) [self authorize:page];
    if (active) {
        for (ASPAdSurface *surface in surfaces) {
            ASPAdCompletionTrackController(surface.owner);
        }
    }
    ASPTimerSetAdActive(active && surfaces.count > 0);
    BOOL needed = active && (surfaces.count || self.pages.count);
    if (!needed && self.timer) {
        dispatch_source_cancel(self.timer);
        self.timer = nil;
    }
    if (needed && !self.timer) {
        self.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(self.timer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), NSEC_PER_SEC / 2, NSEC_PER_SEC / 20);
        __weak AVNRuntime *weak = self;
        dispatch_source_set_event_handler(self.timer, ^{ [weak refresh]; });
        dispatch_resume(self.timer);
    }
}
- (void)requestAdapters {
    @synchronized (self) {
        if (self.refreshQueued) return;
        self.refreshQueued = YES;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        @synchronized (self) { self.refreshQueued = NO; }
        ASPAdCompletionInstallHooks();
        AVNInstallStoreHooks();
        AVNInstallBannerHooks();
        [self refresh];
    });
}
- (void)begin {
    ASPManualSkipConfigure(self.options.enabled && self.options.button && !self.options.automatic);
    ASPAdCompletionConfigure(self.options.automatic && self.options.dismissal);
    ASPAdCompletionInstallHooks();
    AVNInstallStoreHooks();
    AVNInstallBannerHooks();
    ASPTimerConfigure(self.options.enabled && self.options.timers && self.options.automatic);
    for (NSNotificationName event in @[UIApplicationDidBecomeActiveNotification, UIApplicationDidEnterBackgroundNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:event object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *notification) { [self refresh]; }];
    }
}
@end


static void AVNImagesChanged(const struct mach_header *header, intptr_t slide) {
    [AVNRuntime.shared requestAdapters];
}

BOOL AVNRuntimeEnabled(void) {
    return AVNRuntime.shared.options.enabled;
}

void AVNStartRuntime(void) {
    if (AVNRuntimeEnabled()) [AVNRuntime.shared begin];
    _dyld_register_func_for_add_image(AVNImagesChanged);
}

void AVNObserveController(UIViewController *controller) {
    [AVNRuntime.shared observe:controller];
}

void AVNPrepareWebConfiguration(WKWebViewConfiguration *configuration) {
    AVNRuntime *runtime = AVNRuntime.shared;
    if (runtime.options.enabled && runtime.options.inlineVideo && runtime.options.video) {
        configuration.allowsInlineMediaPlayback = YES;
        configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    }
    [runtime prepare:configuration];
}

void AVNMountWebView(WKWebView *view) {
    [AVNRuntime.shared mount:view];
}

float AVNPlaybackRate(float requested) {
    AVNOptions *options = AVNRuntime.shared.options;
    if (!options.enabled || !options.automatic || !options.video ||
        ASPSpeedInternalChange() || !std::isfinite(requested) || requested <= 0) return requested;
    return fminf(ASPSpeedRate(), requested * ASPSpeedRate());
}

void AVNResumePlayer(AVPlayer *player) {
    AVNOptions *options = AVNRuntime.shared.options;
    if (options.enabled && options.automatic && options.video && !ASPSpeedInternalChange()) {
        @try { ASPSpeedSetRate(player, ASPSpeedRate()); } @catch (NSException *exception) {}
        AVNFinishPlaybackRate(player, 1, ASPSpeedRate());
    }
}

BOOL AVNBlocksURL(NSURL *url) {
    return [AVNRuntime.shared blocks:url];
}

BOOL AVNBlocksStoreOverlay(UIWindowScene *scene) {
    AVNOptions *options = AVNRuntime.shared.options;
    if (!options.enabled || !options.hideStore || !NSThread.isMainThread) return NO;
    for (ASPAdSurface *surface in ASPManualSkipAdSurfaces()) {
        if (surface.window.windowScene == scene) return YES;
    }
    return NO;
}

static SKStoreProductViewController *AVNStoreController(UIViewController *controller, NSUInteger *remaining) {
    if (!controller || !*remaining) return nil;
    *remaining -= 1;
    Class store = NSClassFromString(@"SKStoreProductViewController");
    if (store && [controller isKindOfClass:store]) return (SKStoreProductViewController *)controller;
    for (UIViewController *child in controller.childViewControllers) {
        SKStoreProductViewController *found = AVNStoreController(child, remaining);
        if (found) return found;
    }
    return nil;
}

BOOL AVNBlockStorePresentation(UIViewController *presenter, UIViewController *controller, void (^completion)(void)) {
    UIWindow *window = presenter.viewIfLoaded.window;
    if (!window || !AVNBlocksStoreOverlay(window.windowScene)) return NO;
    NSUInteger remaining = 16;
    SKStoreProductViewController *store = AVNStoreController(controller, &remaining);
    if (!store) return NO;
    static char notifiedKey;
    BOOL notify = ![objc_getAssociatedObject(store, &notifiedKey) boolValue];
    objc_setAssociatedObject(store, &notifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    id<SKStoreProductViewControllerDelegate> delegate = store.delegate;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion();
        // Cancel only the product sheet; ad completion and reward callbacks are untouched.
        if (notify && [delegate respondsToSelector:@selector(productViewControllerDidFinish:)]) {
            [delegate productViewControllerDidFinish:store];
        }
    });
    return YES;
}

void AVNFinishPlaybackRate(AVPlayer *player, float requested, float applied) {
    if (applied == requested || requested <= 0 || ASPSpeedInternalChange()) return;
    if (player.rate >= applied * 0.9f) return;
    const float tiers[] = {80.0f, 40.0f, 20.0f, 16.0f, 8.0f, 4.0f, 2.0f};
    for (float candidate : tiers) {
        if (candidate >= applied || candidate <= requested) continue;
        @try { ASPSpeedSetRate(player, candidate); } @catch (NSException *exception) { continue; }
        if (player.rate >= candidate * 0.9f) return;
    }
    @try { ASPSpeedSetRate(player, requested); } @catch (NSException *exception) {}
}

static BOOL AVNBannerBlocking(void) {
    AVNOptions *options = AVNRuntime.shared.options;
    return options.enabled && options.blockBanners;
}

static void AVNRemoveBanner(UIView *banner) {
    if (!NSThread.isMainThread || !AVNBannerBlocking() || !banner.superview) return;
    UIView *parent = banner.superview;
    if ([parent isKindOfClass:UIStackView.class]) [(UIStackView *)parent removeArrangedSubview:banner];
    [banner removeFromSuperview];
}

static void AVNBannerRejected(UIView *banner) {
    AVNRemoveBanner(banner);
    dispatch_async(dispatch_get_main_queue(), ^{
        SEL getter = NSSelectorFromString(@"delegate");
        NSMethodSignature *signature = [banner methodSignatureForSelector:getter];
        if (!signature || signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') return;
        id delegate = ((id (*)(id, SEL))objc_msgSend)(banner, getter);
        SEL callback = NSSelectorFromString(@"bannerView:didFailToReceiveAdWithError:");
        signature = [delegate methodSignatureForSelector:callback];
        if (!signature || signature.numberOfArguments != 4 || signature.methodReturnType[0] != 'v' ||
            [signature getArgumentTypeAtIndex:2][0] != '@' || [signature getArgumentTypeAtIndex:3][0] != '@') return;
        NSError *error = [NSError errorWithDomain:@"com.maxblox2999.advanish" code:1
            userInfo:@{NSLocalizedDescriptionKey: @"Banner blocked by AdVanish."}];
        ((void (*)(id, SEL, id, id))objc_msgSend)(delegate, callback, banner, error);
    });
}

void AVNInstallBannerHooks(void) {
    if (!NSThread.isMainThread) return;
    static NSMutableSet<NSString *> *installed;
    if (!installed) installed = NSMutableSet.set;
    for (NSString *name in @[@"GADBannerView", @"GAMBannerView", @"DFPBannerView"]) {
        Class cls = NSClassFromString(name);
        if (!cls || ![cls isSubclassOfClass:UIView.class]) continue;
        for (NSString *methodName in @[@"loadRequest:", @"didMoveToSuperview"]) {
            NSString *key = [name stringByAppendingString:methodName];
            if ([installed containsObject:key]) continue;
            SEL selector = NSSelectorFromString(methodName);
            Method method = class_getInstanceMethod(cls, selector);
            BOOL load = [methodName isEqualToString:@"loadRequest:"];
            if (!method || method_getNumberOfArguments(method) != (load ? 3 : 2)) continue;
            char type[16] = {};
            method_getReturnType(method, type, sizeof(type));
            if (strcmp(type, @encode(void))) continue;
            if (load) {
                method_getArgumentType(method, 2, type, sizeof(type));
                if (type[0] != '@') continue;
            }
            IMP original = method_getImplementation(method);
            IMP replacement;
            if (load) {
                replacement = imp_implementationWithBlock(^(UIView *banner, id request) {
                    if (AVNBannerBlocking()) { AVNBannerRejected(banner); return; }
                    ((void (*)(id, SEL, id))original)(banner, selector, request);
                });
            } else {
                replacement = imp_implementationWithBlock(^(UIView *banner) {
                    ((void (*)(id, SEL))original)(banner, selector);
                    AVNRemoveBanner(banner);
                });
            }
            if (!class_addMethod(cls, selector, replacement, method_getTypeEncoding(method))) {
                class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(method));
            }
            [installed addObject:key];
        }
    }
}
