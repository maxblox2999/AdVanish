# Verification

The shared web engine has 58 Node VM regression tests covering manual-only behavior, media eligibility, source changes, failed and silently ignored seeks, asynchronous seeks, duplicate injection, timer/clock behavior, side-effect-free cross-frame discovery, single-use action tokens, stale/spoofed replies, token expiry, bounded retries, ambiguity, loop handling and the absence of generic MRAID closing. Run them with:

```sh
node scripts/embed-web.cjs
node --test tests/web.test.cjs
```

The checked-in C++ header must exactly match web/adspeed.js. The workflow checks this before compiling.

Each successful package job checks Debian metadata and installation layout, both arm64/arm64e slices, the iOS 15 deployment minimum, code-signature load-command presence and tweak-loader linkage. These are static package checks; signature-command presence does not prove cryptographic validity or device compatibility.

Native compilation results are recorded in public Actions logs. A passing build does not prove ad skipping, reward handling or UI behavior on a device. No device results are claimed yet for iOS 15–18 or 26.

## Real-browser fixtures

Twelve live Microsoft Edge 156.0.4314.42 cases passed with an isolated profile, real HTML video and cross-origin frames. The locally generated 12-second H264 clip sought once and naturally emitted ended, including in a child frame. Multiple targets abstained, stale snapshots invalidated, concurrent token reuse acted once, and no MRAID close or JavaScript error occurred. An ignored seek restored looping and reported failure; retrying through the native browser setter reached natural completion. This checks Chromium media behavior, not iOS WebKit or real SDK rewards.

Run `node tests/browser/verify.cjs` with Node.js 22+ and Microsoft Edge on Windows, or set `BROWSER_PATH` to a Chromium browser executable. The runner uses two local HTTP origins and its own temporary browser profile, closes its browser afterward and writes `dist/browser.json`. It is included in the source so the browser checks can be repeated independently.

## Native iOS Simulator fixture

On macOS with an installed iOS Simulator runtime, run:

```sh
python3 scripts/test-ios.py --video tests/ios/fixture.mp4
```

This compiles the production native files into an isolated UIKit fixture, creates a temporary simulator, runs the checks, writes `dist/ios-simulator.json` and deletes its simulator. The rootless Actions job runs the same fixture and includes its result in the artifact. It checks visible AppLovin-style ownership, unchanged playback before pressing, a real AVPlayer seek/end event, a repeat press while a mocked reward is pending and the app's own working Close button. It does not test injection, a real ad SDK, remote reward validation or jailbreak compatibility. The 12-second H264 fixture is locally generated, has no audio and contains no proprietary media.

## Device checks still needed

- Confirm the floating button appears and can be dragged in portrait and landscape, on both scene-based and legacy-window apps.
- Check taps outside the button, foreground/background transitions and app relaunches.
- Confirm normal video, audio-only playback, timers and clocks remain unchanged before pressing the button.
- Test native video, web video including cross-origin frames, repeated ads, pause/cancel, playables, close gates and actual rewards.
- Check native video with a non-video web postitial, hidden/offscreen preloaders, multiple scenes, partially covering windows, and media replacement during a pending request. View/layer visibility is sampled and still requires device verification.
- Verify the rootless and rootful packages on their matching jailbreak layouts. Treat iOS 26 as experimental with a low chance of working.

A manual request can select ordinary media if that is what is currently visible or playing. The code does not fabricate reward/completion events, activate SDK Close/Skip controls or forcibly dismiss an SDK's controller. Video completion does not prove reward eligibility. Wait for the app's countdown or reward and use its own Close button when available. Native player requests freeze the original item and recheck the current scene/surface during readiness retries. Some close/reward gates remain outside the shared media interfaces.

## Analysis provenance

The supplied AdSpeed 2.2.1.2 dylib had SHA-256 `7bf6dc5f2a884719af6a6a3d2f91c551bb8ba432d45d3eaecadc38a2ee6b582a`. Direct Ghidra 12.1.4 analysis recovered 31 arm64 function bodies. All 179 decoded hook-table entries matched the selected upstream fork in class, selector, order and stub type. This established the reviewed implementation paths, not a reproducible full-build identity.

Seven user-supplied IPAs were inventoried with REA and supplemental static parsing, followed by direct Ghidra decompilation of selected ad-controller implementations in every sample. Their plists all declared iOS 18.0 minima. Those samples do not establish older-iOS runtime compatibility. None of the games, their binaries, assets, decompiled pseudocode or private data are part of this repository or a build input. See [ANALYSIS.md](ANALYSIS.md) for the findings used by the detector.

References: [Theos rootless layout](https://theos.dev/docs/rootless), [HTML media seeking](https://html.spec.whatwg.org/multipage/media.html#seeking), [IAB MRAID 3.0](https://dev.iabtechlab.com/wp-content/uploads/2018/06/MRAID_3.0_FINAL_June_2018.pdf).
