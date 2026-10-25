#pragma once
#import <WebKit/WebKit.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#ifdef __cplusplus
extern "C" {
#endif
void ASPManualSkipConfigure(BOOL enabled);
void ASPManualSkipTrackWebView(WKWebView *view);
void ASPManualSkipTrackController(UIViewController *controller);
BOOL ASPManualSkipIsAdPlayer(AVPlayer *player);
#ifdef __cplusplus
}
#endif
