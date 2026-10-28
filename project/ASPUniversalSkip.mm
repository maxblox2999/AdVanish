// AdVanish contributions: Copyright (C) 2026 maxblox2999.
// GPL-3.0-only with origin terms; see LICENSE and NOTICE.md.

#import "ASPUniversalSkip.h"
#import "ASPAdSurface.h"
#import "ASPSpeed.h"
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>
#include <math.h>

static char kStateKey;
static thread_local BOOL internalRateChange;

float ASPSpeedRate(void) { return 16.0f; }
BOOL ASPSpeedInternalChange(void) { return internalRateChange; }

void ASPSpeedSetRate(AVPlayer *player, float rate) {
    BOOL previous = internalRateChange;
    internalRateChange = YES;
    @try {
        player.rate = rate;
    } @finally {
        internalRateChange = previous;
    }
}

@interface ASPSkipRequest : NSObject
@property (nonatomic, weak) AVPlayerItem *item;
@property (nonatomic, weak) UIView *root;
@property (nonatomic, weak) UIWindow *window;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) NSTimeInterval deadline;
@property (nonatomic) BOOL pending;
@property (nonatomic) BOOL mayWait;
@property (nonatomic) NSUInteger attempts;
@property (nonatomic) NSUInteger speedAttempts;
@property (nonatomic) NSTimeInterval lastAttempt;
@property (nonatomic) NSUInteger rateGeneration;
@property (nonatomic) BOOL manualRateActive;
@property (nonatomic) float originalRate;
@property (nonatomic) float appliedRate;
@property (nonatomic, copy) void (^completion)(NSString *);
@property (nonatomic, copy) BOOL (^isCurrent)(void);
@end
@implementation ASPSkipRequest
@end

static void finish(ASPSkipRequest *state, NSString *message) {
    state.pending = NO;
    void (^completion)(NSString *) = state.completion;
    state.completion = nil;
    state.isCurrent = nil;
    if (completion) completion(message);
}

static ASPSkipRequest *stateFor(AVPlayer *player) {
    ASPSkipRequest *state = objc_getAssociatedObject(player, &kStateKey);
    if (!state) {
        state = [ASPSkipRequest new];
        objc_setAssociatedObject(player, &kStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (state.item != player.currentItem) {
        state.rateGeneration += 1;
        if (state.manualRateActive && player.rate > 0 && fabsf(player.rate - state.appliedRate) <= 0.01f) {
            ASPSpeedSetRate(player, state.originalRate);
        }
        state.manualRateActive = NO;
        state.generation += 1;
        state.attempts = 0;
        state.speedAttempts = 0;
        state.lastAttempt = 0;
        state.item = player.currentItem;
        finish(state, @"Media changed");
    }
    return state;
}

void ASPSpeedPrepareRate(AVPlayer *player) {
    if ([NSThread isMainThread]) stateFor(player);
}

static BOOL playing(AVPlayer *player) {
    return [UIApplication sharedApplication].applicationState == UIApplicationStateActive &&
           isfinite(player.rate) && player.rate > 0 &&
           player.timeControlStatus != AVPlayerTimeControlStatusPaused;
}

static BOOL videoItem(AVPlayerItem *item) {
    for (AVPlayerItemTrack *track in item.tracks) {
        if (track.enabled && [track.assetTrack.mediaType isEqualToString:AVMediaTypeVideo]) return YES;
    }
    return NO;
}

static BOOL finiteVideo(AVPlayerItem *item) {
    if (!CMTIME_IS_NUMERIC(item.duration)) return NO;
    double duration = CMTimeGetSeconds(item.duration);
    if (!isfinite(duration) || duration <= 0.5) return NO;
    return YES;
}

static BOOL visibleOwner(AVPlayer *player, ASPSkipRequest *state) {
    UIView *root = state.root;
    UIWindow *window = state.window;
    return root && window && root.window == window && !window.hidden &&
        (!window.windowScene || window.windowScene.activationState == UISceneActivationStateForegroundActive) &&
        ASPSurfaceOwnsPlayer(root, player);
}

static BOOL stillOwned(AVPlayer *player, ASPSkipRequest *state) {
    return state.isCurrent && state.isCurrent() && visibleOwner(player, state);
}

static void releaseManualRate(AVPlayer *player, ASPSkipRequest *state, AVPlayerItem *item,
                              NSUInteger generation, float originalRate, NSTimeInterval deadline) {
    if (state.rateGeneration != generation) return;
    if (player.currentItem != item || !playing(player) || !visibleOwner(player, state) ||
        NSProcessInfo.processInfo.systemUptime >= deadline || fabsf(player.rate - state.appliedRate) > 0.01f) {
        state.rateGeneration += 1;
        state.manualRateActive = NO;
        // Never resume a player paused by the app or at its natural end.
        if (player.rate > 0 && fabsf(player.rate - state.appliedRate) <= 0.01f) ASPSpeedSetRate(player, originalRate);
        return;
    }
    __weak AVPlayer *weakPlayer = player;
    __weak AVPlayerItem *weakItem = item;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
        AVPlayer *current = weakPlayer;
        if (current) releaseManualRate(current, state, weakItem, generation, originalRate, deadline);
    });
}

void ASPSpeedTrackRate(AVPlayer *player, UIView *root, float originalRate, float appliedRate) {
    if (![NSThread isMainThread] || !root || !isfinite(originalRate) || originalRate <= 0 ||
        !isfinite(appliedRate) || appliedRate <= 0 || !ASPSurfaceOwnsPlayer(root, player)) return;
    ASPSkipRequest *state = stateFor(player);
    if (fabsf(player.rate - appliedRate) > 0.01f) return;
    state.root = root;
    state.window = root.window;
    state.originalRate = originalRate;
    state.appliedRate = appliedRate;
    state.manualRateActive = YES;
    NSUInteger generation = ++state.rateGeneration;
    double duration = CMTIME_IS_NUMERIC(player.currentItem.duration) ?
        CMTimeGetSeconds(player.currentItem.duration) : 300;
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime +
        fmin(300.0, fmax(10.0, duration / appliedRate + 10.0));
    releaseManualRate(player, state, player.currentItem, generation, state.originalRate, deadline);
}

void ASPSpeedAcceleratePlayer(AVPlayer *player, UIView *root) {
    if (![NSThread isMainThread] || !playing(player) || !ASPSurfaceOwnsPlayer(root, player)) return;
    AVPlayerItem *item = player.currentItem;
    if (item.status != AVPlayerItemStatusReadyToPlay || !videoItem(item) || !finiteVideo(item) ||
        player.timeControlStatus != AVPlayerTimeControlStatusPlaying || player.rate >= ASPSpeedRate()) return;
    ASPSkipRequest *state = stateFor(player);
    if (state.speedAttempts >= 8) return;
    state.speedAttempts += 1;
    float original = state.manualRateActive ? state.originalRate : player.rate;
    ASPSpeedSetRate(player, ASPSpeedRate());
    if (player.currentItem != item) return;
    if (fabsf(player.rate - ASPSpeedRate()) <= 0.01f) {
        state.speedAttempts = 0;
        ASPSpeedTrackRate(player, root, original, ASPSpeedRate());
    } else if (player.rate > 0 && player.rate != original) {
        ASPSpeedSetRate(player, original);
    }
}

static void attempt(AVPlayer *player, AVPlayerItem *item, NSUInteger generation) {
    ASPSkipRequest *state = stateFor(player);
    if (!state.pending || state.generation != generation || state.item != item) return;
    if (!playing(player) || !stillOwned(player, state)) {
        finish(state, @"Ad changed");
        return;
    }
    if (item.status == AVPlayerItemStatusFailed ||
        [NSProcessInfo processInfo].systemUptime >= state.deadline) {
        finish(state, @"Video unavailable");
        return;
    }
    if (item.status == AVPlayerItemStatusReadyToPlay && item.tracks.count && !videoItem(item)) {
        finish(state, @"No visible video");
        return;
    }
    if (item.status != AVPlayerItemStatusReadyToPlay || !videoItem(item) ||
        player.timeControlStatus != AVPlayerTimeControlStatusPlaying || !finiteVideo(item) ||
        !CMTIME_IS_NUMERIC(player.currentTime)) {
        if (!state.mayWait) {
            finish(state, @"Video not ready");
            return;
        }
        __weak AVPlayer *weakPlayer = player;
        __weak AVPlayerItem *weakItem = item;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), dispatch_get_main_queue(), ^{
            if (state.generation != generation || !state.pending) return;
            AVPlayer *currentPlayer = weakPlayer;
            AVPlayerItem *currentItem = weakItem;
            if (currentPlayer && currentItem) attempt(currentPlayer, currentItem, generation);
            else finish(state, @"Media changed");
        });
        return;
    }
    if (player.rate >= ASPSpeedRate()) {
        finish(state, @"Already at 16x");
        return;
    }
    state.attempts += 1;
    state.lastAttempt = NSProcessInfo.processInfo.systemUptime;
    state.speedAttempts = 0;
    ASPSpeedAcceleratePlayer(player, state.root);
    finish(state, state.manualRateActive ? @"Playing at 16x" : @"Speed unsupported");
}

NSArray<AVPlayer *> *ASPUniversalSkipCandidates(NSArray<AVPlayer *> *players, UIView *root,
                                               NSMapTable<AVPlayer *, AVPlayerItem *> *items) {
    NSMutableArray<AVPlayer *> *candidates = [NSMutableArray array];
    for (AVPlayer *player in players) {
        if (!playing(player) || !player.currentItem ||
            [items objectForKey:player] != player.currentItem || !ASPSurfaceOwnsPlayer(root, player)) continue;
        if (player.currentItem.status == AVPlayerItemStatusReadyToPlay && player.currentItem.tracks.count &&
            !videoItem(player.currentItem)) continue;
        [candidates addObject:player];
    }
    return candidates;
}

void ASPUniversalSkipNow(NSArray<AVPlayer *> *players, UIView *root,
                         NSMapTable<AVPlayer *, AVPlayerItem *> *items,
                         BOOL mayWait,
                         BOOL (^isCurrent)(void), void (^completion)(NSString *)) {
    NSCAssert([NSThread isMainThread], @"Manual actions must run on the main thread");
    if (!isCurrent || !isCurrent()) {
        completion(@"Ad changed");
        return;
    }
    NSArray<AVPlayer *> *candidates = ASPUniversalSkipCandidates(players, root, items);
    if (candidates.count != 1) {
        completion(candidates.count ? @"Multiple videos" : @"No visible video");
        return;
    }
    AVPlayer *selected = candidates.firstObject;
    ASPSkipRequest *state = stateFor(selected);
    if (state.pending || state.attempts >= 3 ||
        (state.attempts && [NSProcessInfo processInfo].systemUptime - state.lastAttempt < 1.0)) {
        completion(state.pending ? @"Request pending" : @"Retry limit");
        return;
    }
    state.generation += 1;
    state.pending = YES;
    state.mayWait = mayWait;
    state.root = root;
    state.window = root.window;
    state.completion = completion;
    state.isCurrent = isCurrent;
    state.deadline = [NSProcessInfo processInfo].systemUptime + 5.0;
    NSUInteger generation = state.generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (state.pending && state.generation == generation) {
            finish(state, @"Request timed out");
        }
    });
    attempt(selected, state.item, generation);
}
