# AdVanish

A manual **Fast-forward ad** button for jailbroken iOS apps. It discovers one unambiguous native or HTML video and requests 2x playback after you press it. Since 0.2.1 the button does not jump to the end, which could leave an SDK on a black screen with a failed reward. Decompiled SDK paths improve ownership detection; a visible-media fallback covers other SDKs without a class-name match. The app controls its own closing and rewards.

Enable an app in **Settings > AdVanish**, reopen it, then press the floating button during an ad. Drag the button to move it. Manual mode leaves normal playback, timers and clocks unchanged until you press it. It leaves SDK countdowns unchanged even after pressing. Legacy blocking and acceleration remain available when the manual button is disabled.

Discovery makes no media changes. A request acts only after native players, webviews and child frames have been checked and their snapshots validated. Multiple candidates, missing frame responses, changed sources and incomplete discovery leave the ad alone. Looping web creatives are left unchanged; rejected speed changes report failure. Wait for the app's countdown or reward and use its own Close button when available. Playables, unsupported playback speeds, app-controlled close gates and server-validated rewards can reject or ignore the request. The generic fallback cannot prove that visible media is an ad. Pressing the button during ordinary video can accelerate that video. This is not a promise that every ad can be removed or every reward preserved.

## Compatibility

| iOS | Status |
| --- | --- |
| 15-18 | Target range for rootless and rootful builds. Device testing is still needed. |
| 26 | Experimental, with a low chance of working. Not device-tested. |

A compatible jailbreak and tweak loader are required. A build's deployment target does not establish jailbreak support. Both packages contain arm64 and arm64e slices and use an iOS 15 deployment minimum. Existing AdSpeed per-app preferences are retained.

## Download or rebuild

Download the rootless or rootful package and complete source from [Releases](https://github.com/maxblox2999/AdVanish/releases). Checksums are supplied with each release. [Actions](https://github.com/maxblox2999/AdVanish/actions) also provides packages for successful builds. Each artifact includes the package, SHA-256 checksums and build details. The source artifact contains the complete project at that commit.

To rebuild your own copy, fork this repository, enable Actions, then run **Build** using **Run workflow**. No signing secrets or private files are required. See [BUILD.md](BUILD.md) for the same local build commands and pinned dependencies.

## Source and verification

All tweak code, preference-panel code, embedded JavaScript, tests and build scripts are included. The supplied game IPAs are not included or needed to compile. Build logs and dependency revisions are public. [VALIDATION.md](VALIDATION.md) separates unit tests, package checks and device testing. [AUDIT.md](AUDIT.md) records the release fixes and remaining verification limits.

This project derives from [SoulRune/Un-JailedSpeedAds](https://github.com/SoulRune/Un-JailedSpeedAds) and [maxblox2999/Un-JailedSpeedAds](https://github.com/maxblox2999/Un-JailedSpeedAds), originally based on 34306/JailedSpeedAds. See [NOTICE.md](NOTICE.md) and [LICENSE](LICENSE).
