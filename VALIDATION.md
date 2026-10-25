# Verification

The shared web engine has 34 Node VM regression tests covering manual-only behavior, media eligibility, source changes, failed seeks, duplicate injection, timer/clock behavior, cross-frame message validation and standard MRAID close requests. Run them with:

```sh
node scripts/embed-web.cjs
node --test tests/web.test.cjs
```

The checked-in C++ header must exactly match web/adspeed.js. The workflow checks this before compiling.

Each successful package job checks Debian metadata and installation layout, both arm64/arm64e slices, the iOS 15 deployment minimum, code-signature load-command presence and tweak-loader linkage. These are static package checks; signature-command presence does not prove cryptographic validity or device compatibility.

Native compilation results are recorded in public Actions logs. A passing build does not prove ad skipping, reward handling or UI behavior on a device. No device results are claimed yet for iOS 15–18 or 26.

## Device checks still needed

- Confirm the floating button appears and can be dragged in portrait and landscape, on both scene-based and legacy-window apps.
- Check taps outside the button, foreground/background transitions and app relaunches.
- Confirm normal video, audio-only playback, timers and clocks remain unchanged before pressing the button.
- Test native video, web video including cross-origin frames, repeated ads, pause/cancel, playables, close gates and actual rewards.
- Verify the rootless and rootful packages on their matching jailbreak layouts. Treat iOS 26 as experimental with a low chance of working.

A manual request can select ordinary media if that is what is currently visible or playing. The code does not fabricate reward/completion events or forcibly dismiss an SDK's controller. Some close/reward gates remain outside the shared media interfaces.

## Analysis provenance

The supplied AdSpeed 2.2.1.2 dylib had SHA-256 `7bf6dc5f2a884719af6a6a3d2f91c551bb8ba432d45d3eaecadc38a2ee6b582a`. Direct Ghidra 12.1.4 analysis recovered 31 arm64 function bodies. All 179 decoded hook-table entries matched the selected upstream fork in class, selector, order and stub type. This established the reviewed implementation paths, not a reproducible full-build identity.

Seven user-supplied IPAs were inventoried with REA and supplemental static parsing. Their plists all declared iOS 18.0 minima. Those samples do not establish older-iOS runtime compatibility. None of the games, their binaries, assets or private data are part of this repository or a build input.

References: [Theos rootless layout](https://theos.dev/docs/rootless), [HTML media seeking](https://html.spec.whatwg.org/multipage/media.html#seeking), [IAB MRAID 3.0](https://dev.iabtechlab.com/wp-content/uploads/2018/06/MRAID_3.0_FINAL_June_2018.pdf).
