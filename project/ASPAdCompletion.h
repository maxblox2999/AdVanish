// Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.

#pragma once
#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif
void ASPAdCompletionConfigure(BOOL autoDismiss);
void ASPAdCompletionInstallHooks(void);
void ASPAdCompletionTrackController(UIViewController *controller);
#ifdef __cplusplus
}
#endif
