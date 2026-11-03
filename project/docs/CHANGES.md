# Changes

## 0.8.12

- Fixed reused HTML Close buttons so they can work again when their label changes. Also prevents outdated or duplicate actions.
- Fixed Google fullscreen ads losing track of completion when using Google web components.
- 0.8.12 has a ton of bugs, will fix soon
- 
## 0.8.11

- Added support for detecting Pangle, OpenWrap, Chartboost, and HyprMX controllers, with App Store suppression where needed.
- Improved reused Close buttons so they work when the label changes, without restarting countdowns.

## 0.8.10

- Added an option to block Google AdMob and Ad Manager banners for individual apps.
- Some games may still leave empty space where the banner was. Other banner SDKs aren't supported yet.

## 0.8.9

- Improved handling of multiple Close buttons that appear one after another, including HTML end cards.
- Improved AppLovin playable ad detection and prevented excessive repeated actions.

## 0.8.8

- Added detection for more ad SDK controllers while keeping the existing Close button handling.

## 0.8.5

- Improved detection for more ad SDK controllers. Settings and App Store prompt controls are still supported.

## 0.8.4

- Added an option to hide App Store prompts for individual apps.
- Limited the manual button to one per active app scene.
- Excluded system processes and extensions.

## 0.8.3

- Fixed settings not saving properly. Automatic mode now stays active even when the manual button is hidden.
- Fixed build ordering and improved simulator recovery and retries when builds fail.

## 0.8.0

- Increased ad acceleration to 80x, with a lower speed used when 80x isn't supported.
- Added acceleration for native countdowns and fixed timers being accelerated more than once.
- Disabled apps and manual mode no longer run automatic actions unless enabled or requested.

## 0.6.0

- Restored 16x acceleration for video playback and web timers using Logos hooks.
- Separated the hook generators for jailbreak and injected builds.

## 0.5.3

- Restored Settings categories, preference paths, and MA fullscreen ad detection.
- Added detection for manual web countdowns.

## 0.5.2-rootless-test

- Released a test package for rootless jailbreaks only.
- Settings and all 71 native simulator checks passed on iOS 18.6.
