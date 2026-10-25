#pragma once
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#ifdef __cplusplus
extern "C" {
#endif
void ASPUniversalSkipNow(NSArray<AVPlayer *> *players, UIView *root,
                         NSMapTable<AVPlayer *, AVPlayerItem *> *items,
                         BOOL (^isCurrent)(void), void (^completion)(NSString *));
#ifdef __cplusplus
}
#endif
