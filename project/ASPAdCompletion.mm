// Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.

#import "ASPAdCompletion.h"
#import "ASPManualSkip.h"
#import "AVNDeviceDiagnostics.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>
#include <math.h>

@interface ASPRewardSession : NSObject
@property (nonatomic, weak) id ad;
@property (nonatomic, weak) UIViewController *presenter;
@property (nonatomic, weak) UIViewController *owner;
@property (nonatomic, weak) id creative;
@property (nonatomic) BOOL ownerBound;
@property (nonatomic) BOOL google;
@property (nonatomic) BOOL unity;
@property (nonatomic) BOOL requiresReward;
@property (nonatomic) BOOL rewarded;
@property (nonatomic) BOOL videoCompleted;
@property (nonatomic, strong) NSMapTable<AVPlayer *, AVPlayerItem *> *videoItems;
@property (nonatomic, strong) NSMutableSet<AVPlayerItem *> *endedItems;
@property (nonatomic) NSUInteger videoCount;
@property (nonatomic) BOOL invalidated;
@property (nonatomic) BOOL closeRequested;
@property (nonatomic) NSUInteger closeCount;
@property (nonatomic, strong) NSMapTable<UIView *, NSMutableSet<NSString *> *> *closeActions;
@property (nonatomic) BOOL webClosePending;
@property (nonatomic) NSUInteger webCloseGeneration;
@property (nonatomic, weak) UIView *lastCloseView;
@property (nonatomic) NSTimeInterval expires;
@end
@implementation ASPRewardSession
@end

@interface ASPCloseTapRegistration : NSObject
@property (nonatomic, weak) UITapGestureRecognizer *gesture;
@property (nonatomic, weak) UIViewController *target;
@property (nonatomic) SEL action;
@property (nonatomic) IMP implementation;
@property (atomic) BOOL invalidated;
@end
@implementation ASPCloseTapRegistration
@end

static BOOL gAutoDismiss;
static NSMutableArray<ASPRewardSession *> *sessions;
static NSMutableSet<NSString *> *installed;
static char kCloseTapRegistration;

static BOOL namedKind(id object, NSString *name) {
    Class cls = NSClassFromString(name);
    return cls && [object isKindOfClass:cls];
}

static id objectValue(id object, SEL selector) {
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2 || strcmp(signature.methodReturnType, "@") != 0) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (NSException *exception) {
        return nil;
    }
}

static NSArray<NSString *> *closeGetterNames(void) {
    static NSArray<NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @[@"closeButton", @"closeButtonView", @"close", @"skipButton",
            @"dismissButton", @"dismissControl", @"xButton"];
    });
    return names;
}

static BOOL appLovinOwner(id owner) {
    return namedKind(objectValue(owner, NSSelectorFromString(@"currentAd")), @"ALAd");
}

static id maxCreative(id ad) {
    if (namedKind(ad, @"ALAd")) return ad;
    if (!namedKind(ad, @"ALMediatedAd") || !namedKind(ad, @"MAAd")) {
        AVN_DEVICE_LOG(@"max-creative", @{@"class": AVNDeviceClassName(ad), @"reason": @"unsupported-ad-class"});
        return nil;
    }
    id wrapper = objectValue(ad, NSSelectorFromString(@"adapterWrapper"));
    if (!namedKind(wrapper, @"ALMediationAdapterWrapper") ||
        objectValue(wrapper, NSSelectorFromString(@"ad")) != ad) {
        AVN_DEVICE_LOG(@"max-creative", @{@"class": AVNDeviceClassName(ad),
            @"wrapper": AVNDeviceClassName(wrapper), @"reason": @"wrapper-ownership"});
        return nil;
    }
    id adapter = objectValue(wrapper, NSSelectorFromString(@"adapter"));
    if (!namedKind(adapter, @"ALAppLovinMediationAdapter")) {
        AVN_DEVICE_LOG(@"max-creative", @{@"class": AVNDeviceClassName(ad),
            @"wrapper": AVNDeviceClassName(wrapper), @"adapter": AVNDeviceClassName(adapter),
            @"reason": @"unsupported-mediation-adapter"});
        return nil;
    }
    id creative = objectValue(adapter, NSSelectorFromString(@"loadedRewardedAd"));
    AVN_DEVICE_LOG(@"max-creative", @{@"class": AVNDeviceClassName(ad),
        @"wrapper": AVNDeviceClassName(wrapper), @"adapter": AVNDeviceClassName(adapter),
        @"creative": AVNDeviceClassName(creative), @"reason": namedKind(creative, @"ALAd") ? @"owned" : @"unsupported-creative"});
    return namedKind(creative, @"ALAd") ? creative : nil;
}

static void retireSession(ASPRewardSession *session) {
    AVN_DEVICE_LOG(@"session-retired", @{@"class": AVNDeviceClassName(session.ad),
        @"owner": AVNDeviceClassName(session.owner), @"rewarded": @(session.rewarded),
        @"closes": @(session.closeCount)});
    session.invalidated = YES;
    session.closeActions = nil;
    session.webClosePending = NO;
    session.webCloseGeneration += 1;
    session.videoItems = nil;
    session.endedItems = nil;
    session.creative = nil;
    session.owner = nil;
}

static void pruneSessions(void) {
    if (!sessions) sessions = [NSMutableArray array];
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    NSIndexSet *expired = [sessions indexesOfObjectsPassingTest:^BOOL(ASPRewardSession *session, NSUInteger index, BOOL *stop) {
        UIViewController *owner = session.owner;
        BOOL detached = session.ownerBound && (!owner || !owner.viewIfLoaded.window);
        BOOL changedCreative = !session.google && !session.unity && (!session.creative ||
            objectValue(owner, NSSelectorFromString(@"currentAd")) != session.creative ||
            maxCreative(session.ad) != session.creative);
        return !session.ad || session.expires <= now || session.invalidated ||
            detached || changedCreative;
    }];
    [expired enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
        retireSession(sessions[index]);
    }];
    [sessions removeObjectsAtIndexes:expired];
    while (sessions.count >= 16) {
        retireSession(sessions.firstObject);
        [sessions removeObjectAtIndex:0];
    }
}

static BOOL sameOwner(ASPRewardSession *session, ASPAdSurface *surface) {
    if (surface.owner != session.owner || !ASPAdSurfaceUnchanged(surface)) return NO;
    if (session.google || session.unity) return YES;
    id creative = session.creative;
    return creative && maxCreative(session.ad) == creative && surface.creative == creative;
}

static BOOL belongsToPresenter(UIViewController *owner, UIViewController *presenter) {
    if (!presenter || (presenter.viewIfLoaded.window &&
        owner.viewIfLoaded.window != presenter.viewIfLoaded.window)) return NO;
    UIViewController *node = owner;
    for (NSUInteger depth = 0; node && depth < 64; depth++) {
        if (node == presenter) return YES;
        node = node.parentViewController ?: node.presentingViewController;
    }
    return NO;
}

static BOOL videoSurfaceMatches(ASPRewardSession *session, ASPAdSurface *surface) {
    if (surface.webViews.count || surface.players.count != session.videoCount) return NO;
    for (AVPlayer *player in surface.players) {
        AVPlayerItem *item = [session.videoItems objectForKey:player];
        if (!item || player.currentItem != item) return NO;
    }
    return YES;
}

static BOOL completedVideoSurfaceMatches(ASPRewardSession *session, ASPAdSurface *surface) {
    if (!session.videoCompleted || !session.videoCount || session.endedItems.count != session.videoCount) return NO;
    for (AVPlayer *player in surface.players) {
        AVPlayerItem *item = player.currentItem;
        if (![session.endedItems containsObject:item] || player.rate != 0) return NO;
        double duration = CMTimeGetSeconds(item.duration);
        double current = CMTimeGetSeconds(player.currentTime);
        if (!isfinite(duration) || !isfinite(current) || duration <= 0 || current < duration - 0.05) return NO;
    }
    return YES;
}

static BOOL noArgumentAction(id target, SEL action, IMP *implementation) {
    if (!target || !action) return NO;
    Method method = class_getInstanceMethod(object_getClass(target), action);
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char type[16] = {};
    method_getReturnType(method, type, sizeof(type));
    if (strcmp(type, @encode(void)) != 0) return NO;
    if (implementation) *implementation = method_getImplementation(method);
    return YES;
}

static ASPCloseTapRegistration *eligibleCloseTap(UIView *close, UIViewController *owner) {
    ASPCloseTapRegistration *registration = objc_getAssociatedObject(close, &kCloseTapRegistration);
    UITapGestureRecognizer *gesture = registration.gesture;
    IMP implementation = NULL;
    if (!registration || registration.invalidated || registration.target != owner || !appLovinOwner(owner) ||
        ![gesture isMemberOfClass:UITapGestureRecognizer.class] || !gesture.enabled || gesture.view != close ||
        gesture.numberOfTapsRequired != 1 || gesture.numberOfTouchesRequired != 1 ||
        !noArgumentAction(owner, registration.action, &implementation) || implementation != registration.implementation) return nil;
    NSUInteger taps = 0;
    for (UIGestureRecognizer *candidate in close.gestureRecognizers) {
        if ([candidate isKindOfClass:UITapGestureRecognizer.class] && candidate.enabled) taps += 1;
    }
    return taps == 1 ? registration : nil;
}

static void closeIfEligible(ASPRewardSession *session);

static void scheduleNextClose(ASPRewardSession *session) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 10), dispatch_get_main_queue(), ^{
        closeIfEligible(session);
    });
}

static BOOL sessionVisible(ASPRewardSession *session, WKWebView *page) {
    if (!gAutoDismiss || session.invalidated || !session.ad ||
        session.expires <= NSProcessInfo.processInfo.systemUptime) return NO;
    for (ASPAdSurface *surface in ASPManualSkipAdSurfaces()) {
        if (sameOwner(session, surface) && [surface.webViews containsObject:page] &&
            ASPViewVisibleInSurface(page, surface.root)) return YES;
    }
    return NO;
}

static void closeWebEndCard(ASPRewardSession *session, ASPAdSurface *surface) {
    if (session.webClosePending || surface.webViews.count != 1 || session.closeCount >= 8) {
        AVN_DEVICE_LOG(@"web-close", @{@"class": AVNDeviceClassName(surface.owner),
            @"web": @(surface.webViews.count), @"pending": @(session.webClosePending),
            @"closes": @(session.closeCount), @"reason": @"request-ineligible"});
        return;
    }
    WKWebView *page = surface.webViews.firstObject;
    if (!sessionVisible(session, page)) return;
    session.webClosePending = YES;
    NSUInteger generation = ++session.webCloseGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (session.webCloseGeneration == generation) {
            session.webCloseGeneration += 1;
            session.webClosePending = NO;
        }
    });
    [page callAsyncJavaScript:@"return window.__adspeed && window.__adspeed.inspectClose ? window.__adspeed.inspectClose() : null"
        arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld completionHandler:^(id value, NSError *error) {
        if (session.webCloseGeneration != generation) return;
        AVN_DEVICE_LOG(@"web-close-inspect", @{@"class": AVNDeviceClassName(session.owner),
            @"error": @(error.code), @"valueClass": AVNDeviceClassName(value),
            @"tokenReturned": @([value isKindOfClass:NSString.class] && [value length] > 0)});
        if (error || ![value isKindOfClass:NSString.class] || ![value length] ||
            [value length] > 192 || !sessionVisible(session, page)) {
            session.webClosePending = NO;
            return;
        }
        [page callAsyncJavaScript:@"return window.__adspeed && window.__adspeed.closeCompletedAd ? window.__adspeed.closeCompletedAd(token) : false"
            arguments:@{@"token": value} inFrame:nil inContentWorld:WKContentWorld.pageWorld
            completionHandler:^(id handled, NSError *failure) {
            if (session.webCloseGeneration != generation) return;
            session.webClosePending = NO;
            AVN_DEVICE_LOG(@"web-close-result", @{@"class": AVNDeviceClassName(session.owner),
                @"error": @(failure.code), @"handled": @([handled isEqual:@YES])});
            if (!failure && [handled isEqual:@YES]) {
                session.closeCount += 1;
                scheduleNextClose(session);
            }
        }];
    }];
}

static BOOL exposedClose(UIView *close, ASPAdSurface *surface) {
    if (!close || !close.userInteractionEnabled || !ASPViewVisibleInSurface(close, surface.root)) return NO;
    CGPoint point = [close convertPoint:CGPointMake(CGRectGetMidX(close.bounds), CGRectGetMidY(close.bounds))
                                 toView:close.window];
    UIView *hit = [close.window hitTest:point withEvent:nil];
    if (hit != close && ![hit isDescendantOfView:close]) return NO;
    if ([close isKindOfClass:UIControl.class]) {
        UIControl *control = (UIControl *)close;
        return control.enabled && (control.allControlEvents & UIControlEventTouchUpInside) && control.allTargets.count;
    }
    return eligibleCloseTap(close, surface.owner) != nil;
}

static BOOL closeLabel(UIView *view) {
    NSString *label = view.accessibilityLabel;
    if (!label.length && [view isKindOfClass:UIButton.class]) label = [(UIButton *)view currentTitle];
    label = [[label stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    if ([@[@"x", @"×", @"✕", @"✖"] containsObject:label ?: @""]) {
        CGRect rect = [view convertRect:view.bounds toView:view.window];
        CGRect bounds = view.window.bounds;
        if (CGRectGetMidY(rect) > CGRectGetHeight(bounds) * 0.25 ||
            (CGRectGetMidX(rect) > CGRectGetWidth(bounds) * 0.25 && CGRectGetMidX(rect) < CGRectGetWidth(bounds) * 0.75)) return NO;
    }
    return [@[@"close", @"close ad", @"dismiss", @"dismiss ad", @"x", @"×", @"✕", @"✖",
        @"fermer", @"cerrar", @"schließen", @"fechar", @"chiudi", @"閉じる", @"닫기", @"关闭", @"關閉"] containsObject:label ?: @""];
}


#if defined(AVN_DEVICE_DIAGNOSTICS) && AVN_DEVICE_DIAGNOSTICS
static NSString *diagnosticCloseRole(UIView *view) {
    if (!view) return @"missing";
    if (!closeLabel(view)) return @"unrecognized";
    NSString *role = view.accessibilityLabel;
    if (!role.length && [view isKindOfClass:UIButton.class]) role = [(UIButton *)view currentTitle];
    return [[role stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString] ?: @"missing";
}
#endif

static UIView *findCloseControl(ASPAdSurface *surface) {
    for (NSString *name in closeGetterNames()) {
        id value = objectValue(surface.owner, NSSelectorFromString(name));
        if ([value isKindOfClass:UIView.class]) {
            BOOL exposed = exposedClose(value, surface);
            AVN_DEVICE_LOG(@"native-close-getter", @{@"class": AVNDeviceClassName(surface.owner),
                @"selector": name, @"control": AVNDeviceClassName(value),
                @"role": diagnosticCloseRole(value), @"exposed": @(exposed),
                @"controlEnabled": @([value isKindOfClass:UIControl.class] && [(UIControl *)value isEnabled]),
                @"touchUpInside": @([value isKindOfClass:UIControl.class] &&
                    ([(UIControl *)value allControlEvents] & UIControlEventTouchUpInside) != 0),
                @"targets": @([value isKindOfClass:UIControl.class] ? [(UIControl *)value allTargets].count : 0),
                @"tapRegistered": @(eligibleCloseTap(value, surface.owner) != nil)});
            if (exposed) return value;
        }
    }
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:surface.root];
    UIView *selected = nil;
    NSUInteger visited = 0;
    while (pending.count && visited++ < 512) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        if ([view isKindOfClass:UIControl.class] && closeLabel(view) && exposedClose(view, surface)) {
            if (selected && selected != view) return nil;
            selected = view;
        }
        if (pending.count + view.subviews.count > 512) return nil;
        [pending addObjectsFromArray:view.subviews];
    }
    return pending.count ? nil : selected;
}

static NSString *closeActionKey(UIView *close, ASPAdSurface *surface) {
    NSMutableArray<NSString *> *parts = NSMutableArray.array;
    [parts addObject:[NSString stringWithFormat:@"%p", close.superview]];
    if (closeLabel(close)) {
        NSString *label = close.accessibilityLabel;
        if (!label.length && [close isKindOfClass:UIButton.class]) label = [(UIButton *)close currentTitle];
        label = [[label stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
        [parts addObject:[@"role:" stringByAppendingString:label ?: @""]];
    }

    if ([close isKindOfClass:UIControl.class]) {
        UIControl *control = (UIControl *)close;
        for (id target in control.allTargets) {
            for (NSString *action in [control actionsForTarget:target forControlEvent:UIControlEventTouchUpInside]) {
                [parts addObject:[NSString stringWithFormat:@"%p:%@", target, action]];
            }
        }
    } else {
        [parts addObject:[NSString stringWithFormat:@"%p", objc_getAssociatedObject(close, &kCloseTapRegistration)]];
    }
    for (WKWebView *web in surface.webViews) [parts addObject:[NSString stringWithFormat:@"web:%p", web]];
    return [[parts sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@"|"];
}

static void closeIfEligible(ASPRewardSession *session) {
    BOOL eligible = session.unity || (session.requiresReward ? session.rewarded : session.videoCompleted);
    if (!gAutoDismiss || !eligible || session.closeRequested || session.invalidated || session.closeCount >= 8 ||
        session.expires <= NSProcessInfo.processInfo.systemUptime) {
        AVN_DEVICE_LOG(@"close-eligibility", @{@"class": AVNDeviceClassName(session.ad),
            @"owner": AVNDeviceClassName(session.owner), @"automaticDismissal": @(gAutoDismiss),
            @"requiresReward": @(session.requiresReward), @"rewarded": @(session.rewarded),
            @"videoCompleted": @(session.videoCompleted), @"invalidated": @(session.invalidated),
            @"requested": @(session.closeRequested), @"closes": @(session.closeCount),
            @"expired": @(session.expires <= NSProcessInfo.processInfo.systemUptime)});
        return;
    }
    for (ASPAdSurface *surface in ASPManualSkipAdSurfaces()) {
        if (!sameOwner(session, surface)) {
            AVN_DEVICE_LOG(@"close-owner-mismatch", @{@"class": AVNDeviceClassName(session.ad),
                @"owner": AVNDeviceClassName(session.owner), @"surface": AVNDeviceClassName(surface.owner)});
            continue;
        }
        if (session.unity) {
            closeWebEndCard(session, surface);
            return;
        }
        if (!session.requiresReward && !completedVideoSurfaceMatches(session, surface)) {
            session.invalidated = YES;
            return;
        }
        if (session.lastCloseView && !exposedClose(session.lastCloseView, surface)) {
            [session.closeActions removeObjectForKey:session.lastCloseView];
            session.lastCloseView = nil;
        }
        UIView *close = findCloseControl(surface);
        if (!close) {
            AVN_DEVICE_LOG(@"native-close-missing", @{@"class": AVNDeviceClassName(surface.owner),
                @"web": @(surface.webViews.count), @"players": @(surface.players.count)});
            closeWebEndCard(session, surface);
            return;
        }
        if (!session.closeActions) session.closeActions = [NSMapTable weakToStrongObjectsMapTable];
        NSString *key = closeActionKey(close, surface);
        NSMutableSet<NSString *> *actions = [session.closeActions objectForKey:close];
        if ([actions containsObject:key] || (actions.count && !closeLabel(close))) {
            AVN_DEVICE_LOG(@"native-close-duplicate", @{@"class": AVNDeviceClassName(surface.owner),
                @"control": AVNDeviceClassName(close), @"role": diagnosticCloseRole(close)});
            closeWebEndCard(session, surface);
            return;
        }
        if (!actions) {
            actions = NSMutableSet.set;
            [session.closeActions setObject:actions forKey:close];
        }
        [actions addObject:key];
        session.closeCount += 1;
        session.lastCloseView = close;
        session.closeRequested = YES;
        AVN_DEVICE_LOG(@"native-close-action", @{@"class": AVNDeviceClassName(surface.owner),
            @"control": AVNDeviceClassName(close), @"role": diagnosticCloseRole(close),
            @"closes": @(session.closeCount)});
        @try {
            if ([close isKindOfClass:UIControl.class]) {
                [(UIControl *)close sendActionsForControlEvents:UIControlEventTouchUpInside];
            } else {
                ASPCloseTapRegistration *registration = eligibleCloseTap(close, surface.owner);
                if (registration) ((void (*)(id, SEL))objc_msgSend)(registration.target, registration.action);
            }
        } @finally {
            session.closeRequested = NO;
        }
        scheduleNextClose(session);
        return;
    }
}

static void observeReward(ASPRewardSession *session) {
    AVN_DEVICE_LOG(@"reward-observed", @{@"class": AVNDeviceClassName(session.ad),
        @"owner": AVNDeviceClassName(session.owner), @"tracked": @(session && [sessions containsObject:session]),
        @"expired": @(session.expires <= NSProcessInfo.processInfo.systemUptime)});
    if (!session || ![sessions containsObject:session] || session.expires <= NSProcessInfo.processInfo.systemUptime) return;
    session.rewarded = YES;
    closeIfEligible(session);
}

static ASPRewardSession *googleSession(id ad, UIViewController *presenter, BOOL requiresReward) {
    pruneSessions();
    if (!presenter) {
        for (UIWindow *window in ASPManualSkipContentWindows()) {
            if (!window.keyWindow) continue;
            UIViewController *front = window.rootViewController;
            while (front.presentedViewController) front = front.presentedViewController;
            if (presenter && presenter != front) return nil;
            presenter = front;
        }
    }
    if (!presenter) {
        AVN_DEVICE_LOG(@"google-session", @{@"class": AVNDeviceClassName(ad), @"reason": @"no-presenter"});
        return nil;
    }
    AVN_DEVICE_LOG(@"google-session", @{@"class": AVNDeviceClassName(ad),
        @"presenter": AVNDeviceClassName(presenter), @"requiresReward": @(requiresReward), @"reason": @"created"});
    for (ASPRewardSession *previous in sessions.copy) {
        if (previous.google && previous.presenter == presenter) {
            retireSession(previous);
            [sessions removeObjectIdenticalTo:previous];
        }
    }
    ASPRewardSession *session = [ASPRewardSession new];
    session.ad = ad;
    session.presenter = presenter;
    session.google = YES;
    session.requiresReward = requiresReward;
    session.expires = NSProcessInfo.processInfo.systemUptime + 600;
    [sessions addObject:session];
    return session;
}

static void observeMAXDisplay(id ad) {
    pruneSessions();
    id creative = maxCreative(ad);
    if (!creative) {
        AVN_DEVICE_LOG(@"max-display", @{@"class": AVNDeviceClassName(ad), @"reason": @"no-owned-creative"});
        return;
    }
    NSArray<ASPAdSurface *> *surfaces = ASPManualSkipAdSurfaces();
    // A mediated ad without a concrete owned AppLovin surface is unsupported here.
    ASPAdSurface *owned = nil;
    for (ASPAdSurface *surface in surfaces) {
        if (!appLovinOwner(surface.owner) || surface.creative != creative) continue;
        if (owned) {
            AVN_DEVICE_LOG(@"max-display", @{@"class": AVNDeviceClassName(ad), @"reason": @"ambiguous-owner"});
            return;
        }
        owned = surface;
    }
    if (!owned) {
        AVN_DEVICE_LOG(@"max-display", @{@"class": AVNDeviceClassName(ad),
            @"creative": AVNDeviceClassName(creative), @"surfaces": @(surfaces.count), @"reason": @"no-matching-owner"});
        return;
    }
    AVN_DEVICE_LOG(@"max-display", @{@"class": AVNDeviceClassName(ad),
        @"creative": AVNDeviceClassName(creative), @"owner": AVNDeviceClassName(owned.owner), @"reason": @"created"});
    for (ASPRewardSession *existing in sessions.copy) {
        if (existing.ad == ad && sameOwner(existing, owned)) return;
        if (!existing.google && existing.owner == owned.owner) {
            retireSession(existing);
            [sessions removeObjectIdenticalTo:existing];
        }
    }
    ASPRewardSession *session = [ASPRewardSession new];
    session.ad = ad;
    session.requiresReward = YES;
    session.owner = owned.owner;
    session.ownerBound = YES;
    session.creative = owned.creative;
    session.expires = NSProcessInfo.processInfo.systemUptime + 600;
    [sessions addObject:session];
}

static void observeMAXReward(id ad) {
    pruneSessions();
    AVN_DEVICE_LOG(@"max-reward", @{@"class": AVNDeviceClassName(ad), @"sessions": @(sessions.count)});
    for (ASPRewardSession *session in sessions.copy) {
        if (!session.google && session.ad == ad) observeReward(session);
    }
}

static void captureVideoItems(ASPRewardSession *session) {
    if (session.requiresReward || session.invalidated || session.videoCompleted) return;
    for (ASPAdSurface *surface in ASPManualSkipAdSurfaces()) {
        if (!sameOwner(session, surface)) continue;
        if (surface.webViews.count || (session.videoCount && !videoSurfaceMatches(session, surface))) {
            session.invalidated = YES;
            return;
        }
        if (session.videoCount) return;
        NSMapTable<AVPlayer *, AVPlayerItem *> *items = [NSMapTable weakToStrongObjectsMapTable];
        for (AVPlayer *player in surface.players) {
            AVPlayerItem *item = player.currentItem;
            if (!item || item.status != AVPlayerItemStatusReadyToPlay) continue;
            for (AVPlayerItemTrack *track in item.tracks) {
                if (track.enabled && [track.assetTrack.mediaType isEqualToString:AVMediaTypeVideo]) {
                    [items setObject:item forKey:player];
                    break;
                }
            }
        }
        if (items.count) {
            session.videoItems = items;
            session.videoCount = items.count;
            session.endedItems = [NSMutableSet set];
        }
    }
}

static void observeVideoEnd(AVPlayerItem *item) {
    for (ASPRewardSession *session in sessions.copy) {
        if (session.requiresReward || !session.videoCount || session.closeRequested || session.invalidated) continue;
        BOOL currentOwner = NO;
        for (ASPAdSurface *surface in ASPManualSkipAdSurfaces()) {
            if (!sameOwner(session, surface)) continue;
            if (!videoSurfaceMatches(session, surface)) session.invalidated = YES;
            else currentOwner = YES;
        }
        if (!currentOwner || session.invalidated) continue;
        for (AVPlayer *player in session.videoItems.keyEnumerator) {
            if (player.currentItem == item && [session.videoItems objectForKey:player] == item) {
                [session.endedItems addObject:item];
            }
        }
        if (session.endedItems.count == session.videoCount) {
            session.videoCompleted = YES;
            closeIfEligible(session);
        }
    }
}

static BOOL voidObjects(Method method, NSUInteger objects) {
    if (!method || method_getNumberOfArguments(method) != objects + 2) return NO;
    char type[32] = {};
    method_getReturnType(method, type, sizeof(type));
    if (strcmp(type, @encode(void)) != 0) return NO;
    for (NSUInteger index = 2; index < objects + 2; index++) {
        method_getArgumentType(method, (unsigned int)index, type, sizeof(type));
        if (type[0] != '@') return NO;
    }
    return YES;
}

static BOOL replace(Class cls, SEL selector, IMP replacement, const char *encoding) {
    if (!installed) installed = [NSMutableSet set];
    NSString *key = [NSString stringWithFormat:@"%p:%s", (__bridge void *)cls, sel_getName(selector)];
    if ([installed containsObject:key]) {
        imp_removeBlock(replacement);
        return NO;
    }
    if (!class_addMethod(cls, selector, replacement, encoding)) {
        method_setImplementation(class_getInstanceMethod(cls, selector), replacement);
    }
    [installed addObject:key];
    AVN_DEVICE_LOG(@"hook-installed", @{@"class": NSStringFromClass(cls),
        @"selector": NSStringFromSelector(selector)});
    return YES;
}

static void installCloseTapRegistration(void) {
    Class cls = UIView.class;
    SEL selector = NSSelectorFromString(@"al_addTapHandler:toTarget:");
    Method method = class_getInstanceMethod(cls, selector);
    AVN_DEVICE_LOG(@"hook-signature", @{@"class": NSStringFromClass(cls),
        @"selector": NSStringFromSelector(selector), @"encoding": method ? @(method_getTypeEncoding(method)) : @"missing"});
    if (!method || method_getNumberOfArguments(method) != 4) return;
    char type[16] = {};
    method_getReturnType(method, type, sizeof(type));
    if (strcmp(type, @encode(void)) != 0) return;
    method_getArgumentType(method, 2, type, sizeof(type));
    if (strcmp(type, @encode(SEL)) != 0) return;
    method_getArgumentType(method, 3, type, sizeof(type));
    if (type[0] != '@') return;
    IMP original = method_getImplementation(method);
    IMP wrapper = imp_implementationWithBlock(^(UIView *view, SEL action, id target) {
        BOOL track = NO;
        if (NSThread.isMainThread && gAutoDismiss && appLovinOwner(target)) {
            for (NSString *name in closeGetterNames()) {
                if (objectValue(target, NSSelectorFromString(name)) == view) { track = YES; break; }
            }
        }
        NSArray<UIGestureRecognizer *> *before = track ? view.gestureRecognizers.copy : nil;
        ((void (*)(id, SEL, SEL, id))original)(view, selector, action, target);
        if (!track) return;
        objc_setAssociatedObject(view, &kCloseTapRegistration, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        IMP implementation = NULL;
        if (!noArgumentAction(target, action, &implementation)) return;
        UITapGestureRecognizer *added = nil;
        for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
            if ([before containsObject:gesture] || ![gesture isMemberOfClass:UITapGestureRecognizer.class]) continue;
            if (added) return;
            added = (UITapGestureRecognizer *)gesture;
        }
        if (!added) return;
        ASPCloseTapRegistration *registration = [ASPCloseTapRegistration new];
        registration.gesture = added;
        registration.target = target;
        registration.action = action;
        registration.implementation = implementation;
        objc_setAssociatedObject(view, &kCloseTapRegistration, registration, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(added, &kCloseTapRegistration, registration, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
    replace(cls, selector, wrapper, method_getTypeEncoding(method));
}

static void installTapMutationHooks(void) {
    for (NSString *name in @[@"addTarget:action:", @"removeTarget:action:"]) {
        Class cls = UIGestureRecognizer.class;
        SEL selector = NSSelectorFromString(name);
        Method method = class_getInstanceMethod(cls, selector);
        if (!method || method_getNumberOfArguments(method) != 4) continue;
        char type[16] = {};
        method_getReturnType(method, type, sizeof(type));
        if (strcmp(type, @encode(void)) != 0) continue;
        method_getArgumentType(method, 2, type, sizeof(type));
        if (type[0] != '@') continue;
        method_getArgumentType(method, 3, type, sizeof(type));
        if (strcmp(type, @encode(SEL)) != 0) continue;
        BOOL adding = [name isEqualToString:@"addTarget:action:"];
        IMP original = method_getImplementation(method);
        IMP wrapper = imp_implementationWithBlock(^(UIGestureRecognizer *gesture, id target, SEL action) {
            ASPCloseTapRegistration *registration = objc_getAssociatedObject(gesture, &kCloseTapRegistration);
            if (registration && (adding || ((!target || target == registration.target) &&
                (!action || action == registration.action)))) registration.invalidated = YES;
            ((void (*)(id, SEL, id, SEL))original)(gesture, selector, target, action);
        });
        replace(cls, selector, wrapper, method_getTypeEncoding(method));
    }
}

static void hookMAXDelegate(Class cls) {
    SEL display = NSSelectorFromString(@"didDisplayAd:");
    Method method = class_getInstanceMethod(cls, display);
    AVN_DEVICE_LOG(@"hook-signature", @{@"class": NSStringFromClass(cls),
        @"selector": NSStringFromSelector(display), @"valid": @(voidObjects(method, 1)),
        @"encoding": method ? @(method_getTypeEncoding(method)) : @"missing"});
    if (voidObjects(method, 1)) {
        IMP original = method_getImplementation(method);
        IMP wrapper = imp_implementationWithBlock(^(id delegate, id ad) {
            ((void (*)(id, SEL, id))original)(delegate, display, ad);
            AVN_DEVICE_LOG(@"max-display-callback", @{@"class": AVNDeviceClassName(ad),
                @"delegate": AVNDeviceClassName(delegate), @"mainThread": @(NSThread.isMainThread)});
            if ([NSThread isMainThread]) observeMAXDisplay(ad);
        });
        replace(cls, display, wrapper, method_getTypeEncoding(method));
    }
    SEL reward = NSSelectorFromString(@"didRewardUserForAd:withReward:");
    method = class_getInstanceMethod(cls, reward);
    AVN_DEVICE_LOG(@"hook-signature", @{@"class": NSStringFromClass(cls),
        @"selector": NSStringFromSelector(reward), @"valid": @(voidObjects(method, 2)),
        @"encoding": method ? @(method_getTypeEncoding(method)) : @"missing"});
    if (voidObjects(method, 2)) {
        IMP original = method_getImplementation(method);
        IMP wrapper = imp_implementationWithBlock(^(id delegate, id ad, id value) {
            ((void (*)(id, SEL, id, id))original)(delegate, reward, ad, value);
            AVN_DEVICE_LOG(@"max-reward-callback", @{@"class": AVNDeviceClassName(ad),
                @"delegate": AVNDeviceClassName(delegate), @"mainThread": @(NSThread.isMainThread)});
            if ([NSThread isMainThread]) observeMAXReward(ad);
        });
        replace(cls, reward, wrapper, method_getTypeEncoding(method));
    }
}

void ASPAdCompletionInstallHooks(void) {
    installCloseTapRegistration();
    installTapMutationHooks();
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
                if ([notification.object isKindOfClass:AVPlayerItem.class]) observeVideoEnd(notification.object);
            }];
    });
    for (NSString *name in @[@"GADRewardedAd", @"GADRewardedInterstitialAd"]) {
        Class cls = NSClassFromString(name);
        SEL selector = NSSelectorFromString(@"presentFromRootViewController:userDidEarnRewardHandler:");
        Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
        AVN_DEVICE_LOG(@"hook-signature", @{@"class": name,
            @"selector": NSStringFromSelector(selector), @"valid": @(voidObjects(method, 2)),
            @"encoding": method ? @(method_getTypeEncoding(method)) : @"missing"});
        if (!voidObjects(method, 2)) continue;
        char type[32] = {};
        method_getArgumentType(method, 3, type, sizeof(type));
        if (strcmp(type, "@?") != 0) {
            AVN_DEVICE_LOG(@"hook-rejected", @{@"class": name,
                @"selector": NSStringFromSelector(selector), @"reason": @"reward-handler-not-block"});
            continue;
        }
        IMP original = method_getImplementation(method);
        IMP wrapper = imp_implementationWithBlock(^(id ad, UIViewController *presenter, void (^handler)(void)) {
            AVN_DEVICE_LOG(@"google-present", @{@"class": AVNDeviceClassName(ad),
                @"mainThread": @(NSThread.isMainThread), @"handlerPresent": @(handler != nil)});
            ASPRewardSession *session = [NSThread isMainThread] ? googleSession(ad, presenter, YES) : nil;
            void (^forwarded)(void) = handler;
            if (handler) {
                forwarded = ^{
                    handler();
                    if ([NSThread isMainThread]) observeReward(session);
                    else dispatch_async(dispatch_get_main_queue(), ^{ observeReward(session); });
                };
            }
            ((void (*)(id, SEL, UIViewController *, void (^)(void)))original)(ad, selector, presenter, forwarded);
        });
        replace(cls, selector, wrapper, method_getTypeEncoding(method));
    }
    for (NSString *name in @[@"GADInterstitialAd", @"GADAppOpenAd"]) {
        Class cls = NSClassFromString(name);
        SEL selector = NSSelectorFromString(@"presentFromRootViewController:");
        Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
        AVN_DEVICE_LOG(@"hook-signature", @{@"class": name,
            @"selector": NSStringFromSelector(selector), @"valid": @(voidObjects(method, 1)),
            @"encoding": method ? @(method_getTypeEncoding(method)) : @"missing"});
        if (!voidObjects(method, 1)) continue;
        IMP original = method_getImplementation(method);
        IMP wrapper = imp_implementationWithBlock(^(id ad, UIViewController *presenter) {
            if ([NSThread isMainThread]) googleSession(ad, presenter, NO);
            ((void (*)(id, SEL, UIViewController *))original)(ad, selector, presenter);
        });
        replace(cls, selector, wrapper, method_getTypeEncoding(method));
    }
    Class cls = NSClassFromString(@"MARewardedAd");
    SEL selector = NSSelectorFromString(@"setDelegate:");
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    AVN_DEVICE_LOG(@"hook-signature", @{@"class": @"MARewardedAd",
        @"selector": NSStringFromSelector(selector), @"valid": @(voidObjects(method, 1)),
        @"encoding": method ? @(method_getTypeEncoding(method)) : @"missing"});
    if (voidObjects(method, 1)) {
        IMP original = method_getImplementation(method);
        IMP wrapper = imp_implementationWithBlock(^(id ad, id delegate) {
            AVN_DEVICE_LOG(@"max-delegate", @{@"class": AVNDeviceClassName(ad),
                @"delegate": AVNDeviceClassName(delegate), @"mainThread": @(NSThread.isMainThread)});
            if (delegate && [NSThread isMainThread]) hookMAXDelegate(object_getClass(delegate));
            ((void (*)(id, SEL, id))original)(ad, selector, delegate);
        });
        replace(cls, selector, wrapper, method_getTypeEncoding(method));
    }
}

void ASPAdCompletionTrackController(UIViewController *controller) {
    if (![NSThread isMainThread]) return;
    pruneSessions();
    Class unity = NSClassFromString(@"_TtC8UnityAds30WebViewContainerViewController");
    if (gAutoDismiss && unity && object_getClass(controller) == unity && controller.viewIfLoaded.window) {
        BOOL tracked = NO;
        for (ASPRewardSession *session in sessions) {
            if (session.unity && session.owner == controller) tracked = YES;
        }
        if (!tracked) {
            ASPRewardSession *session = [ASPRewardSession new];
            session.ad = controller;
            session.owner = controller;
            session.ownerBound = YES;
            session.unity = YES;
            session.requiresReward = YES;
            session.expires = NSProcessInfo.processInfo.systemUptime + 600;
            [sessions addObject:session];
        }
    }
    BOOL google = namedKind(controller, @"GADFullScreenAdViewController");
    for (ASPRewardSession *session in sessions.copy) {
        if (google && session.google && !session.owner && belongsToPresenter(controller, session.presenter)) {
            session.owner = controller;
            session.ownerBound = YES;
            AVN_DEVICE_LOG(@"google-owner-bound", @{@"class": AVNDeviceClassName(session.ad),
                @"owner": AVNDeviceClassName(controller)});
        }
        if (session.owner == controller) {
            captureVideoItems(session);
            closeIfEligible(session);
        }
    }
}

void ASPAdCompletionConfigure(BOOL autoDismiss) {
    gAutoDismiss = autoDismiss;
}
