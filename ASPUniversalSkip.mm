#import "ASPUniversalSkip.h"
#import "ASPAdSurface.h"
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>
#include <math.h>

static char kStateKey;
static char kEndedKey;

@interface ASPSkipRequest : NSObject
@property (nonatomic, weak) AVPlayerItem *item;
@property (nonatomic, weak) UIView *root;
@property (nonatomic, weak) UIWindow *window;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) NSTimeInterval deadline;
@property (nonatomic) BOOL pending;
@property (nonatomic) BOOL mayWait;
@property (nonatomic) NSUInteger attempts;
@property (nonatomic) NSTimeInterval lastAttempt;
@property (nonatomic, copy) void (^completion)(NSString *);
@property (nonatomic, copy) BOOL (^isCurrent)(void);
@end
@implementation ASPSkipRequest
@end

void ASPUniversalSkipConfigure(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
            object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
            if ([notification.object isKindOfClass:[AVPlayerItem class]]) {
                objc_setAssociatedObject(notification.object, &kEndedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }];
    });
}

BOOL ASPUniversalSkipItemEnded(AVPlayerItem *item) {
    return item && [objc_getAssociatedObject(item, &kEndedKey) boolValue];
}

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
        state.generation += 1;
        state.attempts = 0;
        state.lastAttempt = 0;
        state.item = player.currentItem;
        finish(state, @"Media changed");
    }
    return state;
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

static BOOL targetFor(AVPlayerItem *item, CMTime *target) {
    if (!CMTIME_IS_NUMERIC(item.duration)) return NO;
    double duration = CMTimeGetSeconds(item.duration);
    if (!isfinite(duration) || duration <= 0.5) return NO;
    CMTime candidate = CMTimeMakeWithSeconds(duration - 0.25, 600);
    for (NSValue *value in item.seekableTimeRanges) {
        CMTimeRange range = value.CMTimeRangeValue;
        if (CMTIMERANGE_IS_VALID(range) && CMTIME_IS_NUMERIC(range.start) &&
            CMTIME_IS_NUMERIC(range.duration) && CMTimeRangeContainsTime(range, candidate)) {
            *target = candidate;
            return YES;
        }
    }
    return NO;
}

static BOOL stillOwned(AVPlayer *player, ASPSkipRequest *state) {
    UIView *root = state.root;
    UIWindow *window = state.window;
    return root && window && root.window == window && !window.hidden &&
        state.isCurrent && state.isCurrent() &&
        (!window.windowScene || window.windowScene.activationState == UISceneActivationStateForegroundActive) &&
        ASPSurfaceOwnsPlayer(root, player);
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
    CMTime target = kCMTimeInvalid;
    if (item.status != AVPlayerItemStatusReadyToPlay || !videoItem(item) ||
        player.timeControlStatus != AVPlayerTimeControlStatusPlaying || !targetFor(item, &target) ||
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
    if (CMTimeCompare(player.currentTime, target) >= 0) {
        finish(state, @"Video at end");
        return;
    }
    state.attempts += 1;
    state.lastAttempt = [NSProcessInfo processInfo].systemUptime;
    objc_setAssociatedObject(item, &kEndedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak AVPlayer *weakPlayer = player;
    __weak AVPlayerItem *weakItem = item;
    [player seekToTime:target toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero
        completionHandler:^(BOOL finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            AVPlayer *currentPlayer = weakPlayer;
            AVPlayerItem *currentItem = weakItem;
            if (state.generation != generation || !state.pending) return;
            if (!currentPlayer || !currentItem || currentPlayer.currentItem != currentItem) {
                finish(state, @"Media changed");
                return;
            }
            finish(state, finished ? @"Seek completed" : @"Seek rejected");
        });
    }];
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
        completion(state.pending ? @"Seek pending" : @"Retry limit");
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
