// Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.

#pragma once
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void ASPTimerConfigure(BOOL enabled);
void ASPTimerSetAdActive(BOOL active);
BOOL ASPTimerAccelerating(void);
NSTimeInterval ASPTimerCompress(NSTimeInterval interval);
NSTimeInterval ASPTimerEnter(NSTimeInterval interval);
void ASPTimerExit(void);

#ifdef __cplusplus
}
#endif
