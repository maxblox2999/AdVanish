# Game-ad coverage

The seven supplied IPAs establish embedded SDKs, not every creative they can download. They do not establish 100 different providers.

| Evidence | Providers |
| --- | --- |
| Framework metadata in the supplied samples | AppLovin, InMobi, Moloco, Meta Audience Network |
| Selected native SDK and callback findings | Google Mobile Ads, Unity Ads, ironSource, Vungle |
| Bundled web-resource markers from the earlier local audit | MRAID, VPAID, HSADX, VSDK, Canvas/WebGL |

These sets overlap. Bridges, renderers and mediation adapters are not additional providers. See [sample hashes and findings](ANALYSIS.md) and [versions by game](AD_TYPES.md).

The 0.5.1 audit found:
- Explicitly native-authorized non-MRAID playables were excluded from the existing semantic tap/swipe assistance.
- A manual timing request did not freeze the playable node, allowing a replacement to inherit its speed.

Regression tests cover those contracts. Browser and simulator fixtures use controlled creatives and mocked SDK events. They do not demonstrate compatibility with 100 providers or confirm real-game rewards.

Unsupported cases still include native-only countdowns, fixed-step render loops, worker clocks, trusted-touch requirements and remote reward gates. A real provider result needs a specific SDK version, actual creative and physical-device run.
