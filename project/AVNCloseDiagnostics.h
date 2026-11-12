// Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.
#pragma once

#if defined(AVN_CLOSE_DIAGNOSTICS) && AVN_CLOSE_DIAGNOSTICS
static void AVNCloseRecord(NSDictionary *record) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *path = [paths.firstObject stringByAppendingPathComponent:@"AdVanish-close-controls.log"];
    if (!path) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
    if (!data || data.length > 16384) return;
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) [NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:nil];
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
    @try {
        unsigned long long size = [file seekToEndOfFile];
        if (size + data.length + 1 <= 262144) {
            [file writeData:data];
            [file writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
        }
    } @finally {
        [file closeFile];
    }
}

static void AVNInspectCloseControls(UIViewController *owner) {
    static NSTimeInterval last;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (!owner.viewIfLoaded.window || now - last < 2) return;
    last = now;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:owner.viewIfLoaded];
    NSMutableArray *controls = NSMutableArray.array;
    NSMutableArray<WKWebView *> *pages = NSMutableArray.array;
    for (NSUInteger index = 0; index < queue.count && index < 512; index++) {
        UIView *view = queue[index];
        if (queue.count < 1024) [queue addObjectsFromArray:view.subviews];
        if ([view isKindOfClass:WKWebView.class] && pages.count < 4) [pages addObject:(WKWebView *)view];
        CGRect frame = [view convertRect:view.bounds toView:owner.viewIfLoaded];
        if (![view isKindOfClass:UIControl.class] || frame.origin.y > owner.view.bounds.size.height * 0.25) continue;
        UIControl *control = (UIControl *)view;
        NSMutableArray *actions = NSMutableArray.array;
        for (id target in control.allTargets) {
            [actions addObject:@{@"target": NSStringFromClass(object_getClass(target)) ?: @"",
                @"actions": [control actionsForTarget:target forControlEvent:UIControlEventTouchUpInside] ?: @[]}];
            if (actions.count == 8) break;
        }
        [controls addObject:@{@"class": NSStringFromClass(object_getClass(control)) ?: @"",
            @"label": [(control.accessibilityLabel ?: @"") substringToIndex:MIN(control.accessibilityLabel.length, 80)],
            @"frame": NSStringFromCGRect(frame), @"hidden": @(control.hidden),
            @"enabled": @(control.enabled), @"interactive": @(control.userInteractionEnabled), @"actions": actions}];
        if (controls.count == 32) break;
    }
    NSString *className = NSStringFromClass(object_getClass(owner)) ?: @"";
    AVNCloseRecord(@{@"time": @(now), @"owner": className, @"controls": controls, @"webViews": @(pages.count)});
    for (WKWebView *page in pages) {
        [page evaluateJavaScript:@"JSON.stringify(Array.from(document.querySelectorAll('button,[role=button],[aria-label],div[id]')).slice(0,512).filter(n=>{let r=n.getBoundingClientRect();return r.width>0&&r.height>0&&r.top<innerHeight*.25}).slice(0,32).map(n=>({tag:n.tagName,id:n.id,classes:String(n.className).slice(0,160),label:String(n.getAttribute('aria-label')||n.textContent||'').trim().slice(0,80),disabled:!!n.disabled,frame:[n.getBoundingClientRect().x,n.getBoundingClientRect().y,n.getBoundingClientRect().width,n.getBoundingClientRect().height]})))"
            completionHandler:^(id result, NSError *error) {
                AVNCloseRecord(@{@"owner": className, @"web": [result isKindOfClass:NSString.class] ? result : @"",
                    @"error": error ? @(error.code) : @0});
            }];
    }
}
#else
static inline void AVNInspectCloseControls(UIViewController *owner) {}
#endif
