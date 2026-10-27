#pragma once
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif
float ASPSpeedRate(void);
BOOL ASPSpeedInternalChange(void);
void ASPSpeedSetRate(AVPlayer *player, float rate);
void ASPSpeedPrepareRate(AVPlayer *player);
void ASPSpeedTrackRate(AVPlayer *player, UIView *root, float originalRate, float appliedRate);
void ASPSpeedAcceleratePlayer(AVPlayer *player, UIView *root);
#ifdef __cplusplus
}
#endif
