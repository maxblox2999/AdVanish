# Coverage

Completion hooks exist for Google full-screen ads (rewarded, interstitial, app open) and AppLovin MAX rewarded ads. Unity Ads full-screen containers and recognized web surfaces (MRAID, VPAID, HSADX, VSDK, Canvas/WebGL) get video speed, timer speed and the manual button. Every other network gets app-wide video speed and web timing, not a provider-specific completion path.

Detection markers and mediation adapters do not guarantee every provider or creative.

Known gaps: fixed-step render loops, worker clocks, trusted-touch requirements and remote reward gates. Native `NSTimer` countdowns compress only while an ad surface is active in automatic mode.

Browser and simulator fixtures use controlled creatives and mocked SDK events. A provider result needs a specific SDK version, an actual creative and a physical-device run.
