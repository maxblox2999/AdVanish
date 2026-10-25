# AdVanish

A manual **Skip current ad** button for jailbroken iOS apps. It finds the displayed ad surface, then uses its player, HTML video, ready close/skip control or the standard MRAID close interface. Decompiled SDK paths improve ownership detection; a visible-media fallback covers other SDKs without a class-name match.

Enable an app in **Settings > AdVanish**, reopen it, then press the floating button during an ad. Drag the button to move it. Manual mode leaves normal playback, timers and clocks unchanged until you press it. Legacy blocking and acceleration remain available when the manual button is disabled.

A button press requests video completion or activates an available close/skip action. Requests stay within the selected scene and surface. Offscreen players are excluded, and an empty webview can fall through to its owner's native player after child frames acknowledge the request. Playable ads, nonseekable media, app-controlled close gates and server-validated rewards can reject or ignore it. The generic fallback cannot prove that visible media is an ad. Pressing the button during ordinary video can skip that video. This is not a promise that every ad can be removed or every reward preserved.

## Compatibility

| iOS | Status |
| --- | --- |
| 15-18 | Target range for rootless and rootful builds. Device testing is still needed. |
| 26 | Experimental, with a low chance of working. Not device-tested. |

A compatible jailbreak and tweak loader are required. A build's deployment target does not establish jailbreak support. Both packages contain arm64 and arm64e slices and use an iOS 15 deployment minimum. Existing AdSpeed per-app preferences are retained.

## Download or rebuild

Open [Actions](https://github.com/maxblox2999/AdVanish/actions), select a successful **Build** run and download the rootless or rootful artifact. Each artifact includes the package, SHA-256 checksums and build details. The source artifact contains the complete project at that commit.

To rebuild your own copy, fork this repository, enable Actions, then run **Build** using **Run workflow**. No signing secrets or private files are required. See [BUILD.md](BUILD.md) for the same local build commands and pinned dependencies.

## Source and verification

All tweak code, preference-panel code, embedded JavaScript, tests and build scripts are included. The supplied game IPAs are not included or needed to compile. Build logs and dependency revisions are public. [VALIDATION.md](VALIDATION.md) separates unit tests, package checks and device testing.

This project derives from [SoulRune/Un-JailedSpeedAds](https://github.com/SoulRune/Un-JailedSpeedAds) and [maxblox2999/Un-JailedSpeedAds](https://github.com/maxblox2999/Un-JailedSpeedAds), originally based on 34306/JailedSpeedAds. See [NOTICE.md](NOTICE.md) and [LICENSE](LICENSE).
