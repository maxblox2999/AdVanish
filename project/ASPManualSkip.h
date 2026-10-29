// Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.

#pragma once
#import <WebKit/WebKit.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "ASPAdSurface.h"
#ifdef __cplusplus
extern "C" {
#endif
void ASPManualSkipConfigure(BOOL enabled);
void ASPManualSkipTrackWebView(WKWebView *view);
void ASPManualSkipTrackController(UIViewController *controller);
BOOL ASPManualSkipIsAdPlayer(AVPlayer *player);
NSArray<ASPAdSurface *> *ASPManualSkipAdSurfaces(void);
NSArray<UIWindow *> *ASPManualSkipContentWindows(void);
ASPAdSurface *ASPManualSkipSurfaceForPlayer(AVPlayer *player, BOOL recognizedOnly);
BOOL ASPManualSkipIsAdWebView(WKWebView *view);
// -1: covered/inactive, 0: exposed unknown surface, 1: exposed recognized ad.
NSInteger ASPManualSkipWebViewContext(WKWebView *view);
#ifdef __cplusplus
}
#endif
