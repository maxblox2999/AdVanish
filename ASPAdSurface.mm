#import "ASPAdSurface.h"
#import "ASPUniversalSkip.h"
#import <objc/message.h>
#include <string.h>
#include <math.h>

@implementation ASPAdSurface
@end

static BOOL kindOfNamedClass(id object, NSString *name) {
    Class cls = NSClassFromString(name);
    return cls && [object isKindOfClass:cls];
}

static BOOL adController(UIViewController *controller) {
    // These owners occur in the supplied SDK method lists. Resolve at use time
    // so a framework loaded after the tweak constructor is covered as well.
    for (NSString *name in @[@"GADFullScreenAdViewController", @"ALBaseVideoViewController",
                            @"_TtC8UnityAds30WebViewContainerViewController", @"UADSViewController"]) {
        if (kindOfNamedClass(controller, name)) return YES;
    }
    return NO;
}

BOOL ASPViewVisibleInSurface(UIView *view, UIView *root) {
    UIWindow *window = root.window;
    if (!view || !window || (view != root && ![view isDescendantOfView:root])) return NO;
    CGRect rect = [view convertRect:view.bounds toView:window];
    rect = CGRectIntersection(rect, window.bounds);
    NSUInteger depth = 0;
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        if (++depth > 128 || ancestor.hidden || ancestor.alpha <= 0.01) return NO;
        if (ancestor.clipsToBounds) {
            rect = CGRectIntersection(rect, [ancestor convertRect:ancestor.bounds toView:window]);
        }
    }
    return !CGRectIsNull(rect) && !CGRectIsEmpty(rect);
}

static UIViewController *frontController(UIViewController *controller) {
    for (NSUInteger depth = 0; controller && depth < 64; depth++) {
        UIViewController *next = controller.presentedViewController;
        if (next && !next.isBeingDismissed && next.viewIfLoaded.window) {
            controller = next;
        } else if ([controller isKindOfClass:[UINavigationController class]]) {
            next = [(UINavigationController *)controller visibleViewController];
            if (!next || next == controller) break;
            controller = next;
        } else if ([controller isKindOfClass:[UITabBarController class]]) {
            next = [(UITabBarController *)controller selectedViewController];
            if (!next || next == controller) break;
            controller = next;
        } else {
            break;
        }
    }
    return controller;
}

static UIViewController *findOwner(UIViewController *controller, UIView *root, NSUInteger *remaining) {
    if (!controller || *remaining == 0 || !ASPViewVisibleInSurface(controller.viewIfLoaded, root)) return nil;
    *remaining -= 1;
    for (UIViewController *child in controller.childViewControllers.reverseObjectEnumerator) {
        UIViewController *found = findOwner(child, root, remaining);
        if (found) return found;
    }
    return adController(controller) ? controller : nil;
}

static id objectGetter(id owner, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *signature = [owner methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2 || strcmp(signature.methodReturnType, "@") != 0) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(owner, selector);
    } @catch (NSException *exception) {
        return nil;
    }
}

static AVPlayer *ownedAppLovinPlayer(UIViewController *owner) {
    if (!kindOfNamedClass(owner, @"ALBaseVideoViewController")) return nil;
    // Decompiled avPlayer follows videoPlayer -> videoView -> player.
    id videoView = objectGetter(objectGetter(owner, @"videoPlayer"), @"videoView");
    if (![videoView isKindOfClass:[UIView class]] ||
        !ASPViewVisibleInSurface(videoView, owner.viewIfLoaded)) return nil;
    BOOL exposed = NO;
    UIView *view = videoView;
    for (NSUInteger x = 1; x <= 3 && !exposed; x++) {
        for (NSUInteger y = 1; y <= 3; y++) {
            CGPoint point = [view convertPoint:CGPointMake(CGRectGetMinX(view.bounds) + view.bounds.size.width * x / 4,
                                                          CGRectGetMinY(view.bounds) + view.bounds.size.height * y / 4)
                                        toView:view.window];
            UIView *hit = [view.window hitTest:point withEvent:nil];
            if (hit == view || [hit isDescendantOfView:view]) {
                exposed = YES;
                break;
            }
        }
    }
    if (!exposed) return nil;
    id player = objectGetter(owner, @"avPlayer");
    return [player isKindOfClass:[AVPlayer class]] ? player : nil;
}

BOOL ASPAdSurfaceUnchanged(ASPAdSurface *surface) {
    return surface.root && surface.owner &&
        (!surface.creative || objectGetter(surface.owner, @"currentAd") == surface.creative);
}

UIControl *ASPCompletedVideoCloseControl(ASPAdSurface *surface) {
    UIViewController *owner = surface.owner;
    if (surface.incomplete || !kindOfNamedClass(owner, @"ALBaseVideoViewController") || !surface.creative ||
        !ASPAdSurfaceUnchanged(surface)) return nil;
    id value = objectGetter(owner, @"avPlayer");
    if (![value isKindOfClass:[AVPlayer class]]) return nil;
    AVPlayer *player = value;
    AVPlayerItem *item = player.currentItem;
    if (!item || [surface.items objectForKey:player] != item || !ASPUniversalSkipItemEnded(item) ||
        item.status != AVPlayerItemStatusReadyToPlay || !CMTIME_IS_NUMERIC(item.duration) ||
        !CMTIME_IS_NUMERIC(player.currentTime) || player.rate != 0) return nil;
    double duration = CMTimeGetSeconds(item.duration);
    double position = CMTimeGetSeconds(player.currentTime);
    if (!isfinite(duration) || !isfinite(position) || duration <= 0 || position < duration - 0.05) return nil;
    SEL selector = NSSelectorFromString(@"isVideoFullyWatched");
    NSMethodSignature *signature = [owner methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2 ||
        (strcmp(signature.methodReturnType, "B") != 0 && strcmp(signature.methodReturnType, "c") != 0)) return nil;
    @try {
        if (!((BOOL (*)(id, SEL))objc_msgSend)(owner, selector)) return nil;
    } @catch (NSException *exception) {
        return nil;
    }
    id control = objectGetter(owner, @"closeButton");
    return [control isKindOfClass:[UIControl class]] && ASPViewVisibleInSurface(control, surface.root) ? control : nil;
}

static BOOL layerExposed(CALayer *layer, UIWindow *window) {
    if (!window) return NO;
    for (NSUInteger x = 1; x <= 3; x++) {
        for (NSUInteger y = 1; y <= 3; y++) {
            CGPoint local = CGPointMake(CGRectGetMinX(layer.bounds) + layer.bounds.size.width * x / 4,
                                         CGRectGetMinY(layer.bounds) + layer.bounds.size.height * y / 4);
            CGPoint point = [layer convertPoint:local toLayer:window.layer.superlayer];
            for (CALayer *hit = [window.layer hitTest:point]; hit; hit = hit.superlayer) {
                if (hit == layer) return YES;
            }
        }
    }
    return NO;
}

static void collectLayers(CALayer *layer, CALayer *root, NSMutableOrderedSet<AVPlayer *> *players,
                          NSUInteger *remaining) {
    if (*remaining == 0 || layer.hidden || layer.opacity <= 0.01) return;
    *remaining -= 1;
    CGRect rect = [layer convertRect:layer.bounds toLayer:root];
    if (CGRectIsEmpty(CGRectIntersection(rect, root.bounds))) return;
    if ([layer isKindOfClass:[AVPlayerLayer class]]) {
        AVPlayer *player = [(AVPlayerLayer *)layer player];
        UIWindow *window = [root.delegate isKindOfClass:[UIView class]] ? [(UIView *)root.delegate window] : nil;
        if (player && layerExposed(layer, window)) [players addObject:player];
    }
    for (CALayer *child in layer.sublayers.reverseObjectEnumerator) {
        // UIView-backed sublayers are visited through their view, which applies
        // ancestor clipping and stops at WKWebView's process boundary.
        if ([child.delegate isKindOfClass:[UIView class]]) continue;
        collectLayers(child, root, players, remaining);
    }
}

static void collectViews(UIView *view, UIView *root, NSMutableArray<WKWebView *> *webViews,
                         NSMutableOrderedSet<AVPlayer *> *players, NSUInteger *remaining) {
    if (*remaining == 0 || !ASPViewVisibleInSurface(view, root)) return;
    *remaining -= 1;
    if ([view isKindOfClass:[WKWebView class]]) {
        if (webViews.count < 17) [webViews addObject:(WKWebView *)view];
        return;
    }
    // Frontmost descendants precede a parent's player layer.
    for (UIView *child in view.subviews.reverseObjectEnumerator) {
        collectViews(child, root, webViews, players, remaining);
    }
    collectLayers(view.layer, view.layer, players, remaining);
}

static BOOL blocksLowerWindow(UIWindow *window) {
    // A pass-through overlay must not hide an ad window underneath. An opaque
    // interactive window without media must not expose a lower player's action.
    for (NSUInteger x = 1; x <= 3; x++) {
        for (NSUInteger y = 1; y <= 3; y++) {
            CGPoint point = CGPointMake(CGRectGetMinX(window.bounds) + window.bounds.size.width * x / 4,
                                        CGRectGetMinY(window.bounds) + window.bounds.size.height * y / 4);
            if ([window hitTest:point withEvent:nil]) return YES;
        }
    }
    return NO;
}

BOOL ASPSurfaceOwnsPlayer(UIView *root, AVPlayer *player) {
    if (!root || !player || !ASPViewVisibleInSurface(root, root)) return NO;
    NSMutableOrderedSet<AVPlayer *> *players = [NSMutableOrderedSet orderedSet];
    NSMutableArray<WKWebView *> *webViews = [NSMutableArray array];
    NSUInteger remaining = 4096;
    collectViews(root, root, webViews, players, &remaining);
    if ([players containsObject:player]) return YES;
    for (UIResponder *responder = root; responder; responder = responder.nextResponder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            UIViewController *owner = (UIViewController *)responder;
            return owner.viewIfLoaded == root && ownedAppLovinPlayer(owner) == player;
        }
    }
    return NO;
}

ASPAdSurface *ASPFindAdSurface(NSArray<UIWindow *> *windows, BOOL recognizedOnly) {
    for (UIWindow *window in windows) {
        if (window.hidden || window.alpha <= 0.01 || !window.rootViewController ||
            (window.windowScene && window.windowScene.activationState != UISceneActivationStateForegroundActive)) continue;
        UIViewController *front = frontController(window.rootViewController);
        UIView *root = front.viewIfLoaded;
        if (!ASPViewVisibleInSurface(root, root)) continue;
        NSUInteger remaining = 512;
        UIViewController *owner = findOwner(front, root, &remaining);
        BOOL incompleteOwners = remaining == 0;
        if (recognizedOnly && !owner) {
            if (blocksLowerWindow(window)) return nil;
            continue;
        }
        if (owner) root = owner.viewIfLoaded;
        NSMutableArray<WKWebView *> *webViews = [NSMutableArray array];
        NSMutableOrderedSet<AVPlayer *> *players = [NSMutableOrderedSet orderedSet];
        remaining = 4096;
        collectViews(root, root, webViews, players, &remaining);
        AVPlayer *owned = ownedAppLovinPlayer(owner);
        if (owned) [players addObject:owned];
        if (!owner && !webViews.count && !players.count) {
            if (blocksLowerWindow(window)) return nil;
            continue;
        }
        ASPAdSurface *surface = [ASPAdSurface new];
        surface.root = root;
        surface.owner = owner ?: front;
        surface.incomplete = incompleteOwners || remaining == 0 || webViews.count > 16;
        surface.creative = kindOfNamedClass(owner, @"ALBaseVideoViewController") ? objectGetter(owner, @"currentAd") : nil;
        surface.webViews = webViews;
        surface.players = players.array;
        surface.items = [NSMapTable strongToStrongObjectsMapTable];
        for (AVPlayer *player in surface.players) {
            if (player.currentItem) [surface.items setObject:player.currentItem forKey:player];
        }
        id sdkPlayer = kindOfNamedClass(owner, @"ALBaseVideoViewController") ? objectGetter(owner, @"avPlayer") : nil;
        if ([sdkPlayer isKindOfClass:[AVPlayer class]] && [sdkPlayer currentItem]) {
            [surface.items setObject:[sdkPlayer currentItem] forKey:sdkPlayer];
        }
        return surface;
    }
    return nil;
}
