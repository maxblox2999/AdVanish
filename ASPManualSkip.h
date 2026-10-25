#pragma once
#import <WebKit/WebKit.h>
#ifdef __cplusplus
extern "C" {
#endif
void ASPManualSkipConfigure(BOOL enabled);
void ASPManualSkipTrackWebView(WKWebView *view);
#ifdef __cplusplus
}
#endif
