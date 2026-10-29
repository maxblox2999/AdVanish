// Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#include <cmath>
#import "ASPPaths.h"
#import "ASPManualSkip.h"
#import "ASPSpeed.h"
#import "ASPAdCompletion.h"
#include "AdSpeedWebScript.h"

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
@property (nonatomic) BOOL inlineVideo;
@property (nonatomic) BOOL broadVideo;
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
    NSDictionary *stored;
    for (NSString *file in ASPPrefsPaths(@"com.34306-sr.adspeed")) {
        stored = [NSDictionary dictionaryWithContentsOfFile:file];
        if (stored) break;
    }
    values[@"Enabled"] = stored[@"Enabled"] ?: @YES;
    NSString *prefix = [bundle stringByAppendingString:@"-"];
    for (NSString *key in stored) {
        if ([key hasPrefix:prefix]) values[[key substringFromIndex:prefix.length]] = stored[key];
    }
    values[@"AppEnabled"] = stored[[@"enabled-" stringByAppendingString:bundle]] ?: @NO;
#endif
    BOOL (^flag)(NSString *, BOOL) = ^BOOL(NSString *key, BOOL fallback) {
        id raw = values[key];
        return [raw respondsToSelector:@selector(boolValue)] ? [raw boolValue] : fallback;
    };
    AVNOptions *options = [AVNOptions new];
    options.enabled = flag(@"Enabled", YES);
#ifndef ADSPEED_JAILED
#ifndef ADSPEED_FORCE_ON
    options.enabled = options.enabled && flag(@"AppEnabled", NO);
#endif
#endif
    options.button = flag(@"ManualSkip", YES);
    options.automatic = flag(@"AutomaticAds", !flag(@"ManualSkip", NO));
    options.video = flag(@"SpeedUpVideo", YES);
    options.timers = flag(@"CompressTimers", YES);
    options.clocks = flag(@"AccelerateClock", YES);
    options.interaction = flag(@"AutoInteract", YES);
    options.dismissal = flag(@"AutoDismiss", YES);
    options.redirects = flag(@"BlockRedirects", YES);
    options.inlineVideo = flag(@"ForceInline", NO);
    options.broadVideo = flag(@"SpeedNativeVideo", NO);
    if ([NSBundle.mainBundle.bundlePath.pathExtension isEqualToString:@"appex"]) options.enabled = NO;
    return options;
}
@end

static IMP AVNExchange(Class type, SEL selector, IMP replacement) {
    Method found = class_getInstanceMethod(type, selector);
    if (!found) {
        imp_removeBlock(replacement);
        return NULL;
    }
    IMP previous = method_getImplementation(found);
    if (!class_addMethod(type, selector, replacement, method_getTypeEncoding(found))) {
        method_setImplementation(class_getInstanceMethod(type, selector), replacement);
    }
    return previous;
}

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
            @"rate": @16, @"automatic": @(o.automatic), @"speedVideo": @(o.video),
            @"compressTimers": @(o.timers), @"accelerateClock": @(o.clocks),
            @"forceInline": @(o.inlineVideo), @"recognizedAd": @NO,
            @"autoComplete": @(o.interaction && o.automatic), @"preventRedirects": @(o.redirects),
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
    if (!self.options.redirects || !ASPManualSkipAdSurfaces().count) return NO;
    NSString *scheme = url.scheme.lowercaseString;
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] ||
        [scheme hasPrefix:@"itms-"];
}
- (void)prepare:(WKWebViewConfiguration *)configuration {
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
    ASPManualSkipTrackController(controller);
    ASPAdCompletionTrackController(controller);
    [self refresh];
}
- (void)refresh {
    if (!NSThread.isMainThread) return;
    BOOL active = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    ASPAdCompletionTrackController(nil);
    NSArray<ASPAdSurface *> *surfaces = ASPManualSkipAdSurfaces();
    for (WKWebView *page in self.pages.allObjects) [self authorize:page];
    if (active) {
        for (ASPAdSurface *surface in surfaces) {
            ASPAdCompletionTrackController(surface.owner);
            if (self.options.automatic && self.options.video) {
                for (AVPlayer *player in surface.players) ASPSpeedAcceleratePlayer(player, surface.root);
            }
        }
    }
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
        [self refresh];
    });
}
- (void)begin {
    ASPManualSkipConfigure(self.options.button);
    ASPAdCompletionConfigure(self.options.automatic && self.options.dismissal);
    ASPAdCompletionInstallHooks();
    for (NSNotificationName event in @[UIApplicationDidBecomeActiveNotification, UIApplicationDidEnterBackgroundNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:event object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *notification) { [self refresh]; }];
    }
}
@end

@interface WKWebView (AVNCreation)
- (instancetype)avn_createWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration __attribute__((objc_method_family(init)));
- (instancetype)avn_createWithCoder:(NSCoder *)coder __attribute__((objc_method_family(init)));
@end

@implementation WKWebView (AVNCreation)
- (instancetype)avn_createWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    AVNRuntime *runtime = AVNRuntime.shared;
    if (runtime.options.inlineVideo && runtime.options.video) {
        configuration.allowsInlineMediaPlayback = YES;
        configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    }
    [runtime prepare:configuration];
    return [self avn_createWithFrame:frame configuration:configuration];
}
- (instancetype)avn_createWithCoder:(NSCoder *)coder {
    WKWebView *view = [self avn_createWithCoder:coder];
    [AVNRuntime.shared prepare:view.configuration];
    return view;
}
@end

static void AVNImagesChanged(const struct mach_header *header, intptr_t slide) {
    [AVNRuntime.shared requestAdapters];
}

__attribute__((constructor)) static void AVNInitialize(void) {
    @autoreleasepool {
        AVNRuntime *runtime = AVNRuntime.shared;
        if (!runtime.options.enabled) return;
        __block IMP appearance;
        appearance = AVNExchange(UIViewController.class, @selector(viewDidAppear:), imp_implementationWithBlock(^(UIViewController *controller, BOOL animated) {
            ((void (*)(id, SEL, BOOL))appearance)(controller, @selector(viewDidAppear:), animated);
            [runtime observe:controller];
        }));
        __block IMP rateSetter;
        rateSetter = AVNExchange(AVPlayer.class, @selector(setRate:), imp_implementationWithBlock(^(AVPlayer *player, float rate) {
            BOOL requested = runtime.options.automatic && runtime.options.video && !ASPSpeedInternalChange() && std::isfinite(rate) && rate > 0;
            if (requested) ASPSpeedPrepareRate(player);
            ((void (*)(id, SEL, float))rateSetter)(player, @selector(setRate:), rate);
            if (!requested) return;
            ASPAdSurface *surface = ASPManualSkipSurfaceForPlayer(player, !runtime.options.broadVideo);
            if (surface) ASPSpeedRequestRate(player, surface.root, rate, fminf(16, rate * 16));
        }));
        Method frameAlias = class_getInstanceMethod(WKWebView.class, @selector(avn_createWithFrame:configuration:));
        IMP frameOriginal = AVNExchange(WKWebView.class, @selector(initWithFrame:configuration:), method_getImplementation(frameAlias));
        if (frameOriginal) method_setImplementation(frameAlias, frameOriginal);
        Method coderAlias = class_getInstanceMethod(WKWebView.class, @selector(avn_createWithCoder:));
        IMP coderOriginal = AVNExchange(WKWebView.class, @selector(initWithCoder:), method_getImplementation(coderAlias));
        if (coderOriginal) method_setImplementation(coderAlias, coderOriginal);
        __block IMP mounting;
        mounting = AVNExchange(WKWebView.class, @selector(didMoveToWindow), imp_implementationWithBlock(^(WKWebView *page) {
            ((void (*)(id, SEL))mounting)(page, @selector(didMoveToWindow));
            [runtime mount:page];
        }));
        __block IMP urlOpening;
        urlOpening = AVNExchange(UIApplication.class, @selector(openURL:options:completionHandler:), imp_implementationWithBlock(^(UIApplication *app, NSURL *url, NSDictionary *options, void (^completion)(BOOL)) {
            if ([runtime blocks:url]) {
                if (completion) completion(NO);
            } else {
                ((void (*)(id, SEL, id, id, id))urlOpening)(app, @selector(openURL:options:completionHandler:), url, options, completion);
            }
        }));
        __block IMP legacyOpening;
        legacyOpening = AVNExchange(UIApplication.class, @selector(openURL:), imp_implementationWithBlock(^BOOL(UIApplication *app, NSURL *url) {
            return [runtime blocks:url] ? NO : ((BOOL (*)(id, SEL, id))legacyOpening)(app, @selector(openURL:), url);
        }));
        [runtime begin];
        _dyld_register_func_for_add_image(AVNImagesChanged);
    }
}
