# AdVanish 0.8.0

- Raise native and web acceleration targets from 16x to 80x.
- Keep lower playback rates when a player rejects faster speeds.
- Prevent nested native timer constructors from compressing twice.
- Respect disabled apps and preserve manual mode.
- Check Settings/package versions and require Main guard success before publishing.

80x is a target, not a guaranteed speed for every creative. Native timers in the supported range may include other app tasks. Server waits and rewards remain controlled by the app. Physical-device behavior remains unverified.
