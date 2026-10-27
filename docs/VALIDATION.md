# Tests

Run commands from the repository root.

## Web engine

```sh
node scripts/embed-web.cjs
node --test tests/web.test.cjs
```

Covers manual playback, visibility cleanup, source changes, frame selection, stale tokens, bounded retries and legacy timer/seek behavior. The generated header must match `web/adspeed.js`.

## Real browser

```sh
node tests/browser/verify.cjs
```

Requires Node.js 22+ and Microsoft Edge on Windows. Set `BROWSER_PATH` to use another Chromium executable. Uses local HTTP servers, a temporary profile and the included 12-second H264 fixture. Writes `dist/browser.json` only after every case passes.

Foreground focus is emulated to prevent headless background pausing. Hidden-page handling is also covered by the Node tests.

## iOS Simulator

```sh
python3 scripts/test-ios.py --video tests/ios/fixture.mp4
```

Requires macOS/Xcode and an installed iOS runtime. Compiles the production native files, runs an isolated UIKit/AVPlayer fixture and deletes its simulator afterward. Writes `dist/ios-simulator.json`. The rootless Actions job includes this report.

Checks the floating button, transparent/pass-through windows, real playback, hidden/replaced media, rate cleanup and completion without SDK Close activation. The ad owner and pending reward are mocked.

## Packages and device testing

Actions builds rootless/rootful packages and checks metadata, layout, arm64/arm64e slices, the iOS 15 minimum and tweak-loader linkage. Signature-command presence is checked; it is not a cryptographic verification.

Real-game rewards, jailbreak injection, iOS WebKit, Settings compatibility, orientation and multi-scene behavior still need physical-device tests. iOS 26 remains experimental with a low chance of working.

The tweak does not fabricate rewards or dismiss SDK controllers. Countdown and reward rules stay with the app. Decompiled SDK findings and sample hashes are in [ANALYSIS.md](ANALYSIS.md); game binaries and pseudocode are not included.
