// Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.

#pragma once
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>

@interface ASPAdSurface : NSObject
@property (nonatomic, weak) UIView *root;
@property (nonatomic, weak) UIWindow *window;
@property (nonatomic, weak) UIViewController *owner;
@property (nonatomic, strong) id creative;
@property (nonatomic) BOOL incomplete;
@property (nonatomic) BOOL recognized;
@property (nonatomic, copy) NSArray<WKWebView *> *webViews;
@property (nonatomic, copy) NSArray<AVPlayer *> *players;
@property (nonatomic, strong) NSMapTable<AVPlayer *, AVPlayerItem *> *items;
@end

ASPAdSurface *ASPFindAdSurface(NSArray<UIWindow *> *windows, BOOL recognizedOnly);
BOOL ASPViewVisibleInSurface(UIView *view, UIView *root);
BOOL ASPSurfaceOwnsPlayer(UIView *root, AVPlayer *player);
BOOL ASPAdSurfaceUnchanged(ASPAdSurface *surface);
