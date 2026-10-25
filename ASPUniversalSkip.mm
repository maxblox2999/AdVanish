#import "ASPUniversalSkip.h"
#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#include <math.h>
#include <stdint.h>

static char kStateKey;
static NSHashTable<AVPlayer *> *gPlayers;
static uint64_t gSequence;

@interface ASPSkipRequest : NSObject
@property (nonatomic, weak) AVPlayerItem *item;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) uint64_t lastObserved;
@property (nonatomic) NSTimeInterval deadline;
@property (nonatomic) BOOL pending;
@property (nonatomic) BOOL attempted;
@end
@implementation ASPSkipRequest
@end

static void onMain(dispatch_block_t work) {
    if ([NSThread isMainThread]) work();
    else dispatch_async(dispatch_get_main_queue(), work);
}

static ASPSkipRequest *stateFor(AVPlayer *player) {
    ASPSkipRequest *state = objc_getAssociatedObject(player, &kStateKey);
    if (!state) {
        state = [ASPSkipRequest new];
        objc_setAssociatedObject(player, &kStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (state.item != player.currentItem) {
        state.generation += 1;
        state.pending = NO;
        state.attempted = NO;
        state.item = player.currentItem;
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

static void attempt(AVPlayer *player, AVPlayerItem *item, NSUInteger generation) {
    ASPSkipRequest *state = stateFor(player);
    if (!state.pending || state.generation != generation || state.item != item) return;
    if (!playing(player) || item.status == AVPlayerItemStatusFailed ||
        [NSProcessInfo processInfo].systemUptime >= state.deadline) {
        state.pending = NO;
        return;
    }
    CMTime target = kCMTimeInvalid;
    if (item.status == AVPlayerItemStatusReadyToPlay && item.tracks.count && !videoItem(item)) {
        state.pending = NO;
        return;
    }
    if (item.status != AVPlayerItemStatusReadyToPlay || !videoItem(item) ||
        player.timeControlStatus != AVPlayerTimeControlStatusPlaying || !targetFor(item, &target) ||
        !CMTIME_IS_NUMERIC(player.currentTime)) {
        __weak AVPlayer *weakPlayer = player;
        __weak AVPlayerItem *weakItem = item;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), dispatch_get_main_queue(), ^{
            AVPlayer *currentPlayer = weakPlayer;
            AVPlayerItem *currentItem = weakItem;
            if (currentPlayer && currentItem) attempt(currentPlayer, currentItem, generation);
        });
        return;
    }
    state.pending = NO;
    if (CMTimeCompare(player.currentTime, target) >= 0) return;
    state.attempted = YES;
    __weak AVPlayer *weakPlayer = player;
    __weak AVPlayerItem *weakItem = item;
    [player seekToTime:target toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero
        completionHandler:^(BOOL finished) {
        if (finished) return;
        onMain(^{
            AVPlayer *currentPlayer = weakPlayer;
            AVPlayerItem *currentItem = weakItem;
            if (!currentPlayer || !currentItem) return;
            ASPSkipRequest *currentState = stateFor(currentPlayer);
            if (currentState.generation == generation && currentState.item == currentItem) {
                currentState.attempted = NO;
            }
        });
    }];
}

void ASPUniversalSkipObservePlayer(AVPlayer *player) {
    if (!player) return;
    __weak AVPlayer *weakPlayer = player;
    onMain(^{
        AVPlayer *currentPlayer = weakPlayer;
        if (!currentPlayer) return;
        if (!gPlayers) gPlayers = [NSHashTable weakObjectsHashTable];
        if (![gPlayers containsObject:currentPlayer] && gPlayers.count >= 64) {
            AVPlayer *oldest = nil;
            uint64_t oldestSequence = UINT64_MAX;
            for (AVPlayer *candidate in gPlayers.allObjects) {
                if (stateFor(candidate).lastObserved < oldestSequence) {
                    oldest = candidate;
                    oldestSequence = stateFor(candidate).lastObserved;
                }
            }
            if (oldest) {
                ASPSkipRequest *oldState = stateFor(oldest);
                oldState.generation += 1;
                oldState.pending = NO;
                [gPlayers removeObject:oldest];
            }
        }
        stateFor(currentPlayer).lastObserved = ++gSequence;
        [gPlayers addObject:currentPlayer];
    });
}

void ASPUniversalSkipNow(void) {
    onMain(^{
        AVPlayer *selected = nil;
        uint64_t latest = 0;
        for (AVPlayer *player in gPlayers.allObjects) {
            ASPSkipRequest *state = stateFor(player);
            if (!playing(player) || !state.item || state.lastObserved <= latest) continue;
            if (state.item.status == AVPlayerItemStatusReadyToPlay && state.item.tracks.count &&
                !videoItem(state.item)) continue;
            latest = state.lastObserved;
            selected = player;
        }
        if (!selected) return;
        ASPSkipRequest *state = stateFor(selected);
        if (state.pending || state.attempted) return;
        state.generation += 1;
        state.pending = YES;
        state.deadline = [NSProcessInfo processInfo].systemUptime + 5.0;
        attempt(selected, state.item, state.generation);
    });
}
