# Changes

## 0.8.12

- Reused HTML Close buttons can advance after an eligible label changes, with stale-token and duplicate protection.
- Google fullscreen ads retain their completion owner when hosting a Google web component.

## 0.8.11

- Added Pangle, OpenWrap, Chartboost and HyprMX controller recognition and scoped Store suppression.
- Reused Close controls can advance when an eligible label changes; countdown labels cannot rearm them.

## 0.8.10

- Added optional per-app Google AdMob and Ad Manager banner blocking.
- Game-reserved banner space can remain. Other banner SDKs are not covered.

## 0.8.9

- Added handling for successive native and accessible HTML end-card Close controls.
- Added standalone AppLovin playable ownership checks and bounded repeated actions.

## 0.8.8

- Expanded SDK controller detection and kept the existing Close getters.

## 0.8.5

- Expanded SDK controller detection; retained the Settings and App Store prompt controls.

## 0.8.4

- Added per-app App Store prompt hiding and one manual button per active app scene.
- Excluded system processes and extensions.

## 0.8.3

- Fixed preference saving and kept automatic mode active when the button is hidden.
- Ordered package builds and added simulator recovery and runner retry handling.

## 0.8.0

- Set acceleration to 80x with lower-rate fallback.
- Added native countdown acceleration and prevented duplicate timer compression.
- Kept disabled apps and manual mode idle until enabled or requested.

## 0.6.0

- Restored 16x playback and web timing through Logos hooks.
- Separated jailbreak and injected hook generators.

## 0.5.3

- Restored categorized Settings, preference paths and MA fullscreen detection.
- Added manual web countdown recognition.

## 0.5.2-rootless-test

- Rootless-only test package.
- Settings and 71 native simulator checks passed on iOS 18.6.
