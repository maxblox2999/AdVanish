#import "ASPAdCompletion.h"
#import "ASPManualSkip.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>
#include <math.h>

@interface ASPRewardSession : NSObject
@property (nonatomic, weak) id ad;
@property (nonatomic, weak) UIViewController *presenter;
@property (nonatomic, weak) UIViewController *owner;
@property (nonatomic, strong) id creative;
@property (nonatomic) BOOL google;
@property (nonatomic) BOOL requiresReward;
@property (nonatomic) BOOL rewarded;
@property (nonatomic) BOOL videoCompleted;
@property (nonatomic, strong) NSMapTable<AVPlayer *, AVPlayerItem *> *videoItems;
@property (nonatomic, strong) NSMutableSet<AVPlayerItem *> *endedItems;
@property (nonatomic) NSUInteger videoCount;
@property (nonatomic) BOOL invalidated;
@property (nonatomic) BOOL closeRequested;
@property (nonatomic) NSTimeInterval expires;
@end
@implementation ASPRewardSession
@end

static BOOL gAutoDismiss;
static NSMutableArray<ASPRewardSession *> *sessions;
static NSMutableSet<NSString *> *installed;

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

static void pruneSessions(void) {
    if (!sessions) sessions = [NSMutableArray array];
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    NSIndexSet *expired = [sessions indexesOfObjectsPassingTest:^BOOL(ASPRewardSession *session, NSUInteger index, BOOL *stop) {
        return !session.ad || session.expires <= now || session.closeRequested;
    }];
    [sessions removeObjectsAtIndexes:expired];
    while (sessions.count >= 16) [sessions removeObjectAtIndex:0];
}

static BOOL sameOwner(ASPRewardSession *session, ASPAdSurface *surface) {
    return surface.owner == session.owner && ASPAdSurfaceUnchanged(surface) &&
        (!session.creative || surface.creative == session.creative);
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

static void closeIfEligible(ASPRewardSession *session) {
    BOOL eligible = session.requiresReward ? session.rewarded : session.videoCompleted;
    if (!gAutoDismiss || !eligible || session.closeRequested || session.invalidated ||
        session.expires <= NSProcessInfo.processInfo.systemUptime) return;
    if (!session.requiresReward) {
        if (!session.videoCount || session.videoItems.count != session.videoCount) return;
        for (AVPlayer *player in session.videoItems.keyEnumerator) {
            if (player.currentItem != [session.videoItems objectForKey:player]) return;
        }
    }
    for (ASPAdSurface *surface in ASPManualSkipAdSurfaces()) {
        if (!sameOwner(session, surface)) continue;
        if (!session.requiresReward && !videoSurfaceMatches(session, surface)) {
            session.invalidated = YES;
            return;
        }
        id value = objectValue(surface.owner, NSSelectorFromString(@"closeButton"));
        if (![value isKindOfClass:UIControl.class]) return;
        UIControl *close = value;
        if (!(close.allControlEvents & UIControlEventTouchUpInside) || !close.allTargets.count ||
            !close.enabled || !close.userInteractionEnabled ||
            !ASPViewVisibleInSurface(close, surface.root)) return;
        CGPoint point = [close convertPoint:CGPointMake(CGRectGetMidX(close.bounds), CGRectGetMidY(close.bounds))
                                     toView:close.window];
        UIView *hit = [close.window hitTest:point withEvent:nil];
        if (hit != close && ![hit isDescendantOfView:close]) return;
        // This is the SDK's own action after its real reward event, not a forced dismissal.
        session.closeRequested = YES;
        [close sendActionsForControlEvents:UIControlEventTouchUpInside];
        return;
    }
}

static void observeReward(ASPRewardSession *session) {
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
    if (!presenter) return nil;
    for (ASPRewardSession *previous in sessions.copy) {
        if (previous.google && previous.presenter == presenter) [sessions removeObjectIdenticalTo:previous];
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
    NSArray<ASPAdSurface *> *surfaces = ASPManualSkipAdSurfaces();
    // A mediated ad without a concrete owned AppLovin surface is unsupported here.
    ASPAdSurface *owned = nil;
    for (ASPAdSurface *surface in surfaces) {
        if (!namedKind(surface.owner, @"ALBaseVideoViewController") || surface.creative != ad) continue;
        if (owned) return;
        owned = surface;
    }
    if (!owned) return;
    for (ASPRewardSession *existing in sessions) {
        if (existing.ad == ad && sameOwner(existing, owned)) return;
    }
    ASPRewardSession *session = [ASPRewardSession new];
    session.ad = ad;
    session.requiresReward = YES;
    session.owner = owned.owner;
    session.creative = owned.creative;
    session.expires = NSProcessInfo.processInfo.systemUptime + 600;
    [sessions addObject:session];
}

static void observeMAXReward(id ad) {
    for (ASPRewardSession *session in sessions.copy) {
        if (!session.google && session.ad == ad) observeReward(session);
    }
}

static void captureVideoItems(ASPRewardSession *session) {
    if (session.requiresReward || session.invalidated) return;
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
    return YES;
}

static void hookMAXDelegate(Class cls) {
    SEL display = NSSelectorFromString(@"didDisplayAd:");
    Method method = class_getInstanceMethod(cls, display);
    if (voidObjects(method, 1)) {
        IMP original = method_getImplementation(method);
        IMP wrapper = imp_implementationWithBlock(^(id delegate, id ad) {
            ((void (*)(id, SEL, id))original)(delegate, display, ad);
            if ([NSThread isMainThread]) observeMAXDisplay(ad);
        });
        replace(cls, display, wrapper, method_getTypeEncoding(method));
    }
    SEL reward = NSSelectorFromString(@"didRewardUserForAd:withReward:");
    method = class_getInstanceMethod(cls, reward);
    if (voidObjects(method, 2)) {
        IMP original = method_getImplementation(method);
        IMP wrapper = imp_implementationWithBlock(^(id delegate, id ad, id value) {
            ((void (*)(id, SEL, id, id))original)(delegate, reward, ad, value);
            if ([NSThread isMainThread]) observeMAXReward(ad);
        });
        replace(cls, reward, wrapper, method_getTypeEncoding(method));
    }
}

void ASPAdCompletionInstallHooks(void) {
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
        if (!voidObjects(method, 2)) continue;
        char type[32] = {};
        method_getArgumentType(method, 3, type, sizeof(type));
        if (strcmp(type, "@?") != 0) continue;
        IMP original = method_getImplementation(method);
        IMP wrapper = imp_implementationWithBlock(^(id ad, UIViewController *presenter, void (^handler)(void)) {
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
    if (voidObjects(method, 1)) {
        IMP original = method_getImplementation(method);
        IMP wrapper = imp_implementationWithBlock(^(id ad, id delegate) {
            if (delegate && [NSThread isMainThread]) hookMAXDelegate(object_getClass(delegate));
            ((void (*)(id, SEL, id))original)(ad, selector, delegate);
        });
        replace(cls, selector, wrapper, method_getTypeEncoding(method));
    }
}

void ASPAdCompletionTrackController(UIViewController *controller) {
    if (![NSThread isMainThread]) return;
    pruneSessions();
    BOOL google = namedKind(controller, @"GADFullScreenAdViewController");
    for (ASPRewardSession *session in sessions.copy) {
        if (google && session.google && !session.owner && belongsToPresenter(controller, session.presenter)) {
            session.owner = controller;
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
