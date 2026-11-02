# AdVanish 0.7.0

- Add native NSTimer acceleration in automatic mode.
- Prevent nested timer constructors from applying acceleration twice.
- Respect the global and per-app disable switches for web injection and native playback.
- Keep Logos hooks, broad video/web acceleration and manual mode.

Eligible 0.5–30 second native timers are accelerated while an ad surface is active; this can include unrelated timers. Server waits and rewards remain controlled by the app. Physical-device behavior remains unverified.
