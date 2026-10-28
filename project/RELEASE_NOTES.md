# AdVanish 0.3.0

- Shared 16x speed for automatic acceleration and the manual button.
- Explicit automatic/manual behavior; manual mode waits for the button and never presses Close automatically.
- Gameplay timing and bounded tap/swipe assistance for supported playable controls.
- Nested MRAID frame timing and CSS/Web Animations acceleration, with visibility and pause cleanup.
- Reward-gated SDK Close actions for supported Google and MAX sessions.
- SDK Close after real playback-end events for supported Google native-video interstitials.
- Supported ad redirect blocking; no fabricated reward or completion callbacks.
- Removed legacy SDK blocking and seek-to-tail modes.
- Rootless/rootful packages and a self-contained jailed injection framework, with complete source and rebuild instructions.
- Source and build tools grouped under `project/`; rerunnable Actions artifacts and separate automatic/manual injected checks.

Targets iOS 15–18. iOS 26 is experimental with a low chance of working.

Test release. Unknown playables may still need interaction. Real SDKs, game rewards and signed-device injection remain unverified. See [ad types and limits](https://github.com/maxblox2999/AdVanish/blob/main/project/docs/AD_TYPES.md).
