// Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.
#import "AVNRuntime.h"

%group AVNPlaybackHooks
%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    AVNObserveController(self);
}
%end

%hook AVPlayer
- (void)setRate:(float)rate {
    float applied = AVNPlaybackRate(rate);
    @try {
        %orig(applied);
    } @catch (NSException *exception) {
        if (applied == rate) @throw;
    }
    AVNFinishPlaybackRate(self, rate, applied);
}
- (void)play {
    %orig;
    AVNResumePlayer(self);
}
- (void)playImmediatelyAtRate:(float)rate {
    float applied = AVNPlaybackRate(rate);
    %orig(applied);
    AVNFinishPlaybackRate(self, rate, applied);
}
%end

%hook WKWebView
- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    AVNPrepareWebConfiguration(configuration);
    return %orig;
}
- (instancetype)initWithCoder:(NSCoder *)coder {
    WKWebView *view = %orig;
    AVNPrepareWebConfiguration(view.configuration);
    return view;
}
- (void)didMoveToWindow {
    %orig;
    AVNMountWebView(self);
}
%end

%hook UIApplication
- (void)openURL:(NSURL *)url options:(NSDictionary *)options completionHandler:(void (^)(BOOL))completion {
    if (AVNBlocksURL(url)) {
        if (completion) completion(NO);
        return;
    }
    %orig;
}
- (BOOL)openURL:(NSURL *)url {
    return AVNBlocksURL(url) ? NO : %orig;
}
%end
%end

%ctor {
    @autoreleasepool {
        %init(AVNPlaybackHooks);
        AVNStartRuntime();
    }
}
