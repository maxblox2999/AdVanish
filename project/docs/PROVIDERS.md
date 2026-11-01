# Game-ad coverage

Integration coverage includes AppLovin, Google Mobile Ads, Unity Ads, ironSource and Vungle callback paths, plus recognized web surfaces using MRAID, VPAID, HSADX, VSDK and Canvas/WebGL. Detection markers and mediation adapters do not establish compatibility with every provider or creative.

The 0.5.1 audit found:
- Explicitly native-authorized non-MRAID playables were excluded from the existing semantic tap/swipe assistance.
- A manual timing request did not freeze the playable node, allowing a replacement to inherit its speed.

Regression tests cover those contracts. Browser and simulator fixtures use controlled creatives and mocked SDK events. They do not demonstrate compatibility with 100 providers or confirm real-game rewards.

Unsupported cases still include native-only countdowns, fixed-step render loops, worker clocks, trusted-touch requirements and remote reward gates. A real provider result needs a specific SDK version, actual creative and physical-device run.
