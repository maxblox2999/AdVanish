# AdVanish 0.8.3

- Settings changes go through CFPreferences, so a reopened app sees them.
- Rootless reads the real preferences path first instead of the bootstrap copy.
- Turning off the fast-forward button no longer turns automatic mode off.
- 80x playback with a lower-rate fallback when a player rejects it.
- Native countdown timers accelerate only during a visible ad.
- Run Settings, native, injected and manual simulator checks in parallel.
- Stop recovery when shutdown, reboot or app readiness fails.
- The release tag and package version come from `control`.
