# Tests

Run commands from the repository root.

## Web engine

```sh
node scripts/embed-web.cjs
node --test tests/web.test.cjs
```

Covers combined automatic/manual playback, 16x timing, visibility cleanup, source changes, frame selection, stale tokens, bounded input and rejected rates. The generated header must match `web/adspeed.js`. Seeking to an ad's end is no longer supported.

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

Checks the floating button, transparent/pass-through windows, real 16x playback, hidden/replaced media, rate cleanup and reward-gated SDK Close. SDK owners and reward events are mocked; the player and UIKit controls are real.

With the pinned Theos environment configured, also run the actual injected framework:

```sh
python3 scripts/test-ios.py --video tests/ios/fixture.mp4 --injected --output dist/ios-injected.json
```

This compiles and loads the same jailed framework, including its constructor and Objective-C hooks. It checks ordinary playback, recognized playback and WebKit script installation. It does not use a real ad SDK or Apple provisioning profile.

## IPA tooling

```sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Synthetic IPA and Mach-O fixtures check source preservation, executable permissions, encryption rejection, header bounds, signatures, architecture, unsafe archives and framework dependencies. Preparation is separate from signing and installation.

## Packages and device testing

Actions builds rootless/rootful packages and a jailed framework. Checks cover package metadata, layout, arm64/arm64e jailbreak slices, the iOS 15 minimum, tweak-loader linkage and the jailed framework's system dependencies. Signature-command presence in Debian packages is not a cryptographic verification. The framework's build signature is ad-hoc.

Real-game rewards, jailbreak injection, iOS WebKit, Settings compatibility, orientation and multi-scene behavior still need physical-device tests. iOS 26 remains experimental with a low chance of working.

The tweak observes genuine SDK reward events and uses eligible SDK controls for supported dismissal. It does not fabricate rewards or force controller dismissal. Decompiled SDK findings and sample hashes are in [ANALYSIS.md](ANALYSIS.md); game binaries and pseudocode are not included. [Supported paths](SUPPORT.md).
