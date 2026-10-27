# Code audit

## 0.2.2

- Fixed manual 2× playback continuing after a native video is hidden, detached, moved to another window or left in an inactive scene.
- Web playback now restores its original rate when hidden, removed, covered or paused. Paused videos stay paused.
- DOM cleanup batches mutations into one check per 250 ms while needed. It does not continuously poll in manual mode.
- The browser runner activates its test tab and removes stale results before starting.
- Shortened the README and Settings text. Detailed notes are under `docs/`.

## 0.2.1

Replaced manual end jumps with 2× playback after reports of black screens and failed rewards. Removed automatic SDK Close activation. Added transparent overlays, typed player getters and native simulator checks.

## Verification limits

Browser and simulator checks exercise playback, selection, cleanup and completion. The native fixture uses a mock SDK. These checks do not prove jailbreak injection, real SDK behavior or final game rewards. Physical-device testing is pending.

[Run the tests](VALIDATION.md) · [Decompilation findings](ANALYSIS.md)
