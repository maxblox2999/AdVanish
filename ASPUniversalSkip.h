#pragma once
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#ifdef __cplusplus
extern "C" {
#endif
NSArray<AVPlayer *> *ASPUniversalSkipCandidates(NSArray<AVPlayer *> *players, UIView *root,
                                               NSMapTable<AVPlayer *, AVPlayerItem *> *items);
void ASPUniversalSkipNow(NSArray<AVPlayer *> *players, UIView *root,
                         NSMapTable<AVPlayer *, AVPlayerItem *> *items,
                         BOOL mayWait,
                         BOOL (^isCurrent)(void), void (^completion)(NSString *));
#ifdef __cplusplus
}
#endif
