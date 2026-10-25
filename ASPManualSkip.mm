#import "ASPManualSkip.h"
#import "ASPUniversalSkip.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL gEnabled;
static BOOL gRefreshing;
static NSHashTable<WKWebView *> *gWebViews;
static NSMapTable<UIWindowScene *, UIWindow *> *gWindows;
static UIWindow *gLegacyWindow;
static char kWebSequenceKey;
static NSUInteger gWebSequence;

static void refreshWindows(void);

static WKWebView *frontWebView(UIWindowScene *scene) {
    NSArray<UIWindow *> *windows = scene ? scene.windows : [UIApplication sharedApplication].windows;
    UIWindow *overlay = scene ? [gWindows objectForKey:scene] : gLegacyWindow;
    UIWindow *front = nil;
    for (UIWindow *window in windows) {
        if (window.hidden || window.alpha <= 0.01 || window == gLegacyWindow ||
            window == overlay) continue;
        if (!front || window.windowLevel >= front.windowLevel) front = window;
    }
    WKWebView *selected = nil;
    NSUInteger latest = 0;
    for (WKWebView *view in gWebViews.allObjects) {
        UIWindow *window = view.window;
        if (!window || window.hidden || view.hidden || view.alpha <= 0.01 ||
            window.windowScene.activationState != UISceneActivationStateForegroundActive) continue;
        if (scene && window.windowScene != scene) continue;
        if (front && window != front) continue;
        CGRect visible = CGRectIntersection([view convertRect:view.bounds toView:window], window.bounds);
        if (CGRectIsNull(visible) || CGRectIsEmpty(visible)) continue;
        UIView *hit = [window hitTest:CGPointMake(CGRectGetMidX(visible), CGRectGetMidY(visible)) withEvent:nil];
        if (hit != view && ![hit isDescendantOfView:view]) continue;
        NSUInteger sequence = [objc_getAssociatedObject(view, &kWebSequenceKey) unsignedIntegerValue];
        if (sequence >= latest) {
            latest = sequence;
            selected = view;
        }
    }
    return selected;
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
    self.view.backgroundColor = [UIColor clearColor];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.92];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button setTitle:@"Skip current ad" forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    button.layer.cornerRadius = 18;
    button.accessibilityLabel = @"Skip current ad";
    button.accessibilityHint = @"Requests video completion or a supported ad close action. Drag to reposition.";
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
- (void)skipCurrentAd {
    if (!gEnabled || self.requestPending ||
        [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    self.requestPending = YES;
    NSUInteger generation = ++self.feedbackGeneration;
    [self.skipButton setTitle:@"Skip requested" forState:UIControlStateNormal];
    WKWebView *web = frontWebView(self.view.window.windowScene);
    if (web) {
        [web evaluateJavaScript:@"(function(){return window.__adspeed ? window.__adspeed.skip() : 0;}())"
             completionHandler:nil];
    } else {
        ASPUniversalSkipNow();
    }
    __weak ASPSkipButtonController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        ASPSkipButtonController *controller = weakSelf;
        if (!controller || controller.feedbackGeneration != generation) return;
        controller.requestPending = NO;
        [controller.skipButton setTitle:@"Skip current ad" forState:UIControlStateNormal];
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
    if (!gWebViews) gWebViews = [NSHashTable weakObjectsHashTable];
    if (![gWebViews containsObject:view] && gWebViews.count >= 64) {
        WKWebView *oldest = nil;
        NSUInteger sequence = NSUIntegerMax;
        for (WKWebView *candidate in gWebViews.allObjects) {
            NSUInteger observed = [objc_getAssociatedObject(candidate, &kWebSequenceKey) unsignedIntegerValue];
            if (observed < sequence) {
                oldest = candidate;
                sequence = observed;
            }
        }
        if (oldest) [gWebViews removeObject:oldest];
    }
    objc_setAssociatedObject(view, &kWebSequenceKey, @(++gWebSequence), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gWebViews addObject:view];
}
