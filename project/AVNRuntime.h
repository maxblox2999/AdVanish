// Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.
#pragma once
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <WebKit/WebKit.h>

BOOL AVNRuntimeEnabled(void);
void AVNStartRuntime(void);
void AVNObserveController(UIViewController *controller);
void AVNPrepareWebConfiguration(WKWebViewConfiguration *configuration);
void AVNMountWebView(WKWebView *view);
float AVNPlaybackRate(float requested);
void AVNResumePlayer(AVPlayer *player);
void AVNFinishPlaybackRate(AVPlayer *player, float requested, float applied);
BOOL AVNBlocksURL(NSURL *url);

void AVNInstallStoreHooks(void);
BOOL AVNBlocksStoreOverlay(UIWindowScene *scene);
BOOL AVNBlockStorePresentation(UIViewController *presenter, UIViewController *controller, void (^completion)(void));

void AVNInstallBannerHooks(void);
