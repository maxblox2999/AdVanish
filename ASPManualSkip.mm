#import "ASPManualSkip.h"
#import "ASPUniversalSkip.h"
#import "ASPAdSurface.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

static BOOL gEnabled;
static BOOL gRefreshing;
static NSHashTable<UIWindow *> *gKnownWindows;
static NSMapTable<UIWindowScene *, UIWindow *> *gWindows;
static UIWindow *gLegacyWindow;
static char kWindowSequenceKey;
static NSUInteger gWindowSequence;

static void refreshWindows(void);

static void rememberWindow(UIWindow *window) {
    if (!window) return;
    if (!gKnownWindows) gKnownWindows = [NSHashTable weakObjectsHashTable];
    if (![gKnownWindows containsObject:window] && gKnownWindows.count >= 64) {
        UIWindow *oldest = nil;
        NSUInteger sequence = NSUIntegerMax;
        for (UIWindow *candidate in gKnownWindows.allObjects) {
            NSUInteger observed = [objc_getAssociatedObject(candidate, &kWindowSequenceKey) unsignedIntegerValue];
            if (observed < sequence) {
                oldest = candidate;
                sequence = observed;
            }
        }
        if (oldest) [gKnownWindows removeObject:oldest];
    }
    objc_setAssociatedObject(window, &kWindowSequenceKey, @(++gWindowSequence), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gKnownWindows addObject:window];
}

static NSArray<UIWindow *> *contentWindows(UIWindowScene *scene) {
    NSArray<UIWindow *> *windows = scene ? scene.windows : gKnownWindows.allObjects;
    NSMutableArray<UIWindow *> *content = [NSMutableArray array];
    Class overlay = NSClassFromString(@"ASPSkipWindow");
    for (UIWindow *window in windows) {
        if ([window isKindOfClass:overlay] || window.hidden || window.alpha <= 0.01) continue;
        if (window.windowScene != scene) continue;
        [content addObject:window];
    }
    return [content sortedArrayUsingComparator:^NSComparisonResult(UIWindow *left, UIWindow *right) {
        if (left.windowLevel != right.windowLevel) {
            return left.windowLevel > right.windowLevel ? NSOrderedAscending : NSOrderedDescending;
        }
        NSUInteger a = [objc_getAssociatedObject(left, &kWindowSequenceKey) unsignedIntegerValue];
        NSUInteger b = [objc_getAssociatedObject(right, &kWindowSequenceKey) unsignedIntegerValue];
        if (a != b) return a > b ? NSOrderedAscending : NSOrderedDescending;
        NSUInteger x = [windows indexOfObjectIdenticalTo:left];
        NSUInteger y = [windows indexOfObjectIdenticalTo:right];
        if (x == y) return NSOrderedSame;
        return x > y ? NSOrderedAscending : NSOrderedDescending;
    }];
}

static ASPAdSurface *currentSurface(UIWindowScene *scene) {
    return ASPFindAdSurface(contentWindows(scene), NO);
}

BOOL ASPManualSkipIsAdPlayer(AVPlayer *player) {
    if (![NSThread isMainThread]) return NO;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]] ||
            scene.activationState != UISceneActivationStateForegroundActive) continue;
        ASPAdSurface *surface = ASPFindAdSurface(contentWindows((UIWindowScene *)scene), YES);
        if (surface && !surface.incomplete && ASPSurfaceOwnsPlayer(surface.root, player)) return YES;
    }
    ASPAdSurface *legacy = ASPFindAdSurface(contentWindows(nil), YES);
    return legacy && !legacy.incomplete && ASPSurfaceOwnsPlayer(legacy.root, player);
}

@interface ASPWebSnapshot : NSObject
@property (nonatomic, weak) WKWebView *web;
@property (nonatomic, copy) NSString *token;
@property (nonatomic) NSUInteger count;
@end
@implementation ASPWebSnapshot
@end

static BOOL boundedInteger(id value, NSUInteger maximum) {
    if (![value isKindOfClass:[NSNumber class]]) return NO;
    double number = [value doubleValue];
    return isfinite(number) && number >= 0 && number <= maximum && floor(number) == number;
}

@interface ASPSkipButtonController : UIViewController
@property (nonatomic, strong) UIButton *skipButton;
@property (nonatomic) BOOL positioned;
@property (nonatomic) BOOL requestPending;
@property (nonatomic) NSUInteger feedbackGeneration;
@end

@implementation ASPSkipButtonController
- (void)loadView {
    self.view = [[UIView alloc] initWithFrame:CGRectZero];
    self.view.opaque = NO;
    self.view.backgroundColor = [UIColor clearColor];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.92];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button setTitle:@"Fast-forward ad" forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    button.layer.cornerRadius = 18;
    button.accessibilityLabel = @"Fast-forward ad";
    button.accessibilityHint = @"Requests faster playback of one visible video. The app controls closing and rewards. Drag to reposition.";
    [button addTarget:self action:@selector(skipCurrentAd) forControlEvents:UIControlEventTouchUpInside];
    [button addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(moveButton:)]];
    [self.view addSubview:button];
    self.skipButton = button;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect area = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    if (CGRectIsEmpty(area)) return;
    CGSize size = CGSizeMake(MIN(130, area.size.width), MIN(38, area.size.height));
    CGPoint center = self.positioned ? self.skipButton.center :
        CGPointMake(CGRectGetMaxX(area) - size.width / 2 - 12,
                    CGRectGetMaxY(area) - size.height / 2 - 48);
    center.x = MAX(CGRectGetMinX(area) + size.width / 2, MIN(center.x, CGRectGetMaxX(area) - size.width / 2));
    center.y = MAX(CGRectGetMinY(area) + size.height / 2, MIN(center.y, CGRectGetMaxY(area) - size.height / 2));
    self.skipButton.bounds = (CGRect){CGPointZero, size};
    self.skipButton.center = center;
}
- (void)moveButton:(UIPanGestureRecognizer *)gesture {
    CGPoint movement = [gesture translationInView:self.view];
    CGPoint center = self.skipButton.center;
    self.skipButton.center = CGPointMake(center.x + movement.x, center.y + movement.y);
    [gesture setTranslation:CGPointZero inView:self.view];
    self.positioned = YES;
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}
- (BOOL)surfaceCurrent:(ASPAdSurface *)surface {
    UIView *root = surface.root;
    ASPAdSurface *fresh = currentSurface(self.view.window.windowScene);
    return gEnabled && root && !surface.incomplete && !fresh.incomplete &&
        ASPAdSurfaceUnchanged(surface) && ASPViewVisibleInSurface(root, root) &&
        [UIApplication sharedApplication].applicationState == UIApplicationStateActive &&
        fresh.root == root && [[NSSet setWithArray:fresh.webViews] isEqualToSet:[NSSet setWithArray:surface.webViews]];
}
- (BOOL)nativeSelectionCurrent:(NSArray<AVPlayer *> *)native surface:(ASPAdSurface *)surface {
    if (![self surfaceCurrent:surface]) return NO;
    ASPAdSurface *fresh = currentSurface(self.view.window.windowScene);
    NSArray<AVPlayer *> *current = ASPUniversalSkipCandidates(fresh.players, fresh.root, fresh.items);
    if (![[NSSet setWithArray:current] isEqualToSet:[NSSet setWithArray:native]]) return NO;
    for (AVPlayer *player in native) {
        if ([surface.items objectForKey:player] != player.currentItem) return NO;
    }
    return YES;
}
- (void)finishRequest:(NSString *)message generation:(NSUInteger)generation {
    if (self.feedbackGeneration != generation) return;
    [self.skipButton setTitle:message forState:UIControlStateNormal];
    __weak ASPSkipButtonController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        ASPSkipButtonController *controller = weakSelf;
        if (!controller || controller.feedbackGeneration != generation) return;
        controller.requestPending = NO;
        [controller.skipButton setTitle:@"Fast-forward ad" forState:UIControlStateNormal];
    });
}
- (void)performSelection:(ASPAdSurface *)surface snapshots:(NSArray<ASPWebSnapshot *> *)snapshots
                  native:(NSArray<AVPlayer *> *)native generation:(NSUInteger)generation {
    if (self.feedbackGeneration != generation) return;
    if (![self surfaceCurrent:surface]) {
        [self finishRequest:@"Ad changed" generation:generation];
        return;
    }
    if (![self nativeSelectionCurrent:native surface:surface]) {
        [self finishRequest:@"Media changed" generation:generation];
        return;
    }
    ASPWebSnapshot *selected = nil;
    NSUInteger count = native.count;
    for (ASPWebSnapshot *snapshot in snapshots) {
        count += snapshot.count;
        if (snapshot.count == 1) selected = snapshot;
    }
    if (count == 0) {
        [self finishRequest:@"No eligible video" generation:generation];
        return;
    }
    if (count > 1) {
        [self finishRequest:@"Multiple videos" generation:generation];
        return;
    }
    __weak ASPSkipButtonController *weakSelf = self;
    if (!selected) {
        // A waiting native request cannot keep an empty web snapshot current.
        if (snapshots.count && native.firstObject.currentItem.status != AVPlayerItemStatusReadyToPlay) {
            [self finishRequest:@"Video not ready" generation:generation];
            return;
        }
        ASPUniversalSkipNow(native, surface.root, surface.items, snapshots.count == 0, ^BOOL {
            ASPSkipButtonController *controller = weakSelf;
            return controller && controller.feedbackGeneration == generation && [controller nativeSelectionCurrent:native surface:surface];
        }, ^(NSString *message) {
            [weakSelf finishRequest:message generation:generation];
        });
        return;
    }
    if (!ASPViewVisibleInSurface(selected.web, surface.root)) {
        [self finishRequest:@"Ad changed" generation:generation];
        return;
    }
    [selected.web callAsyncJavaScript:@"return window.__adspeed && typeof window.__adspeed.skipAsync === 'function' ? await window.__adspeed.skipAsync(token) : {handled:0,unresolved:1};"
        arguments:@{@"token": selected.token} inFrame:nil inContentWorld:[WKContentWorld pageWorld]
        completionHandler:^(id result, NSError *error) {
        ASPSkipButtonController *controller = weakSelf;
        if (!controller || controller.feedbackGeneration != generation) return;
        if (![controller surfaceCurrent:surface]) {
            [controller finishRequest:@"Ad changed" generation:generation];
        } else if (error || ![result isKindOfClass:[NSDictionary class]] ||
                   !boundedInteger(result[@"handled"], 1) || !boundedInteger(result[@"unresolved"], 1)) {
            [controller finishRequest:@"Web unavailable" generation:generation];
        } else if ([result[@"handled"] unsignedIntegerValue] == 1) {
            [controller finishRequest:@"Playback requested" generation:generation];
        } else {
            [controller finishRequest:@"Media unavailable" generation:generation];
        }
    }];
}
- (void)validateSnapshots:(NSArray<ASPWebSnapshot *> *)snapshots index:(NSUInteger)index
                 surface:(ASPAdSurface *)surface native:(NSArray<AVPlayer *> *)native
              generation:(NSUInteger)generation {
    if (self.feedbackGeneration != generation) return;
    if (![self surfaceCurrent:surface]) {
        [self finishRequest:@"Ad changed" generation:generation];
        return;
    }
    if (index >= snapshots.count) {
        [self performSelection:surface snapshots:snapshots native:native generation:generation];
        return;
    }
    ASPWebSnapshot *snapshot = snapshots[index];
    if (!ASPViewVisibleInSurface(snapshot.web, surface.root)) {
        [self finishRequest:@"Ad changed" generation:generation];
        return;
    }
    __weak ASPSkipButtonController *weakSelf = self;
    [snapshot.web callAsyncJavaScript:@"return window.__adspeed && typeof window.__adspeed.validateAsync === 'function' ? await window.__adspeed.validateAsync(token) : false;"
        arguments:@{@"token": snapshot.token} inFrame:nil inContentWorld:[WKContentWorld pageWorld]
        completionHandler:^(id result, NSError *error) {
        ASPSkipButtonController *controller = weakSelf;
        if (!controller || controller.feedbackGeneration != generation) return;
        if (error || ![result isKindOfClass:[NSNumber class]] || ![result isEqual:@YES]) {
            [controller finishRequest:@"Media changed" generation:generation];
        } else {
            [controller validateSnapshots:snapshots index:index + 1 surface:surface native:native generation:generation];
        }
    }];
}
- (void)inspectSurface:(ASPAdSurface *)surface index:(NSUInteger)index
            snapshots:(NSMutableArray<ASPWebSnapshot *> *)snapshots native:(NSArray<AVPlayer *> *)native
           generation:(NSUInteger)generation {
    if (self.feedbackGeneration != generation) return;
    if (![self surfaceCurrent:surface]) {
        [self finishRequest:@"Ad changed" generation:generation];
        return;
    }
    if (index >= surface.webViews.count) {
        [self validateSnapshots:snapshots index:0 surface:surface native:native generation:generation];
        return;
    }
    WKWebView *web = surface.webViews[index];
    if (!ASPViewVisibleInSurface(web, surface.root)) {
        [self finishRequest:@"Ad changed" generation:generation];
        return;
    }
    __weak ASPSkipButtonController *weakSelf = self;
    [web callAsyncJavaScript:@"return window.__adspeed && typeof window.__adspeed.inspectAsync === 'function' ? await window.__adspeed.inspectAsync() : {count:0,unresolved:1,token:null};"
        arguments:@{} inFrame:nil inContentWorld:[WKContentWorld pageWorld]
        completionHandler:^(id result, NSError *error) {
        ASPSkipButtonController *controller = weakSelf;
        if (!controller || controller.feedbackGeneration != generation) return;
        if (![controller surfaceCurrent:surface]) {
            [controller finishRequest:@"Ad changed" generation:generation];
        } else if (error || ![result isKindOfClass:[NSDictionary class]] ||
                   !boundedInteger(result[@"count"], 2) || !boundedInteger(result[@"unresolved"], 1) ||
                   [result[@"unresolved"] unsignedIntegerValue] != 0) {
            [controller finishRequest:@"Web unavailable" generation:generation];
        } else if ([result[@"count"] unsignedIntegerValue] > 1) {
            [controller finishRequest:@"Multiple videos" generation:generation];
        } else if (![result[@"token"] isKindOfClass:[NSString class]] ||
                   [result[@"token"] length] == 0 || [result[@"token"] length] > 192) {
            [controller finishRequest:@"Web unavailable" generation:generation];
        } else {
            ASPWebSnapshot *snapshot = [ASPWebSnapshot new];
            snapshot.web = web;
            snapshot.token = result[@"token"];
            snapshot.count = [result[@"count"] unsignedIntegerValue];
            [snapshots addObject:snapshot];
            [controller inspectSurface:surface index:index + 1 snapshots:snapshots native:native generation:generation];
        }
    }];
}
- (void)skipCurrentAd {
    if (!gEnabled || self.requestPending ||
        [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    self.requestPending = YES;
    NSUInteger generation = ++self.feedbackGeneration;
    ASPAdSurface *surface = currentSurface(self.view.window.windowScene);
    if (!surface || surface.incomplete) {
        [self finishRequest:@"No visible ad" generation:generation];
        return;
    }
    [self.skipButton setTitle:@"Checking ad" forState:UIControlStateNormal];
    NSArray<AVPlayer *> *native = ASPUniversalSkipCandidates(surface.players, surface.root, surface.items);
    if (native.count > 1) {
        [self finishRequest:@"Multiple videos" generation:generation];
        return;
    }
    [self inspectSurface:surface index:0 snapshots:[NSMutableArray array] native:native generation:generation];
    __weak ASPSkipButtonController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 25 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        ASPSkipButtonController *controller = weakSelf;
        if (controller.requestPending && controller.feedbackGeneration == generation) {
            controller.feedbackGeneration += 1;
            [controller finishRequest:@"Request timed out" generation:controller.feedbackGeneration];
        }
    });
}
@end

@interface ASPSkipWindow : UIWindow
@end
@implementation ASPSkipWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    UIButton *button = [(ASPSkipButtonController *)self.rootViewController skipButton];
    return (hit == button || [hit isDescendantOfView:button]) ? hit : nil;
}
@end

static void refreshWindows(void) {
    if (gRefreshing) return;
    gRefreshing = YES;
    UIApplication *application = [UIApplication sharedApplication];
    for (UIWindow *window in gWindows.objectEnumerator) window.hidden = YES;
    gLegacyWindow.hidden = YES;
    if (gEnabled && application.applicationState == UIApplicationStateActive) {
        for (UIScene *scene in application.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]] ||
                scene.activationState != UISceneActivationStateForegroundActive) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            UIWindow *window = [gWindows objectForKey:windowScene];
            if (!window) {
                window = [[ASPSkipWindow alloc] initWithWindowScene:windowScene];
                window.opaque = NO;
                window.backgroundColor = [UIColor clearColor];
                window.windowLevel = UIWindowLevelAlert + 1;
                window.rootViewController = [ASPSkipButtonController new];
                [gWindows setObject:window forKey:windowScene];
            }
            window.frame = windowScene.coordinateSpace.bounds;
            window.hidden = NO;
        }
        if (application.connectedScenes.count == 0) {
            if (!gLegacyWindow) {
                gLegacyWindow = [[ASPSkipWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
                gLegacyWindow.opaque = NO;
                gLegacyWindow.backgroundColor = [UIColor clearColor];
                gLegacyWindow.windowLevel = UIWindowLevelAlert + 1;
                gLegacyWindow.rootViewController = [ASPSkipButtonController new];
            }
            gLegacyWindow.frame = [UIScreen mainScreen].bounds;
            gLegacyWindow.hidden = NO;
        }
    }
    gRefreshing = NO;
}

void ASPManualSkipConfigure(BOOL enabled) {
    dispatch_async(dispatch_get_main_queue(), ^{
        gEnabled = enabled;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            gWindows = [NSMapTable weakToStrongObjectsMapTable];
            NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
            NSArray<NSNotificationName> *events = @[
                UIApplicationDidBecomeActiveNotification, UIApplicationDidEnterBackgroundNotification,
                UISceneDidActivateNotification, UISceneWillDeactivateNotification,
                UIWindowDidBecomeVisibleNotification,
            ];
            for (NSNotificationName event in events) {
                [center addObserverForName:event object:nil queue:[NSOperationQueue mainQueue]
                                usingBlock:^(NSNotification *notification) {
                    if ([notification.object isKindOfClass:[ASPSkipWindow class]]) return;
                    if ([notification.object isKindOfClass:[UIWindow class]]) rememberWindow(notification.object);
                    refreshWindows();
                }];
            }
            [center addObserverForName:UISceneDidDisconnectNotification object:nil queue:[NSOperationQueue mainQueue]
                           usingBlock:^(NSNotification *notification) {
                UIWindow *window = [gWindows objectForKey:notification.object];
                window.hidden = YES;
                [gWindows removeObjectForKey:notification.object];
            }];
        });
        refreshWindows();
    });
}

void ASPManualSkipTrackWebView(WKWebView *view) {
    rememberWindow(view.window);
}

void ASPManualSkipTrackController(UIViewController *controller) {
    rememberWindow(controller.viewIfLoaded.window);
}
