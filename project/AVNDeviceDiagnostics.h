// Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.
#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#if defined(AVN_DEVICE_DIAGNOSTICS) && AVN_DEVICE_DIAGNOSTICS
static inline NSString *AVNDeviceClassName(id object) {
    return NSStringFromClass(object_getClass(object)) ?: @"nil";
}
BOOL AVNDeviceDiagnosticsEnabled(void);
void AVNDeviceDiagnosticLog(NSString *event, NSDictionary *fields);
#define AVN_DEVICE_LOG(event, ...) do { if (AVNDeviceDiagnosticsEnabled()) AVNDeviceDiagnosticLog(event, (__VA_ARGS__)); } while (0)
#else
#define AVN_DEVICE_LOG(event, ...) do {} while (0)
#endif
