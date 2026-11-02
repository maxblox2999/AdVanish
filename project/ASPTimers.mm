// Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.

#import "ASPTimers.h"
#import "ASPSpeed.h"
#include <cmath>

// A countdown tick and a one-shot ad wait both live in this window. Shorter
// intervals belong to animation and input handling, longer ones to network
// timeouts and retry backoff, so neither is touched.
static const NSTimeInterval kASPTimerMinimum = 0.5;
static const NSTimeInterval kASPTimerMaximum = 30.0;

static BOOL timerEnabled;
static BOOL adActive;

void ASPTimerConfigure(BOOL enabled) { timerEnabled = enabled; }
void ASPTimerSetAdActive(BOOL active) { adActive = active; }

BOOL ASPTimerAccelerating(void) { return timerEnabled && adActive; }

NSTimeInterval ASPTimerCompress(NSTimeInterval interval) {
    if (!ASPTimerAccelerating() || !isfinite(interval)) return interval;
    if (interval < kASPTimerMinimum || interval > kASPTimerMaximum) return interval;
    float rate = ASPSpeedRate();
    return rate > 1 ? interval / rate : interval;
}
