# AdVanish 0.8.2

- Turning off the fast-forward button no longer turns automatic mode off.
- Settings are saved to every configured preferences path, including rootless.
- 80x playback with 40x/20x/16x/8x/4x/2x fallback when a player rejects it.
- Native countdown timers accelerate only during a visible ad.
- Manual mode waits for a press and never auto-closes.
- Disabled apps skip injection, playback changes and timers.
- Simulator tests reuse one booted device; a wedged simulator is reset instead of hanging the build.
- The release tag and package version come from `control`.
