// AdVanish contributions: Copyright (C) 2026 maxblox2999.
// GPL-3.0-only with origin terms; see LICENSE and NOTICE.md.

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
