# Tests

From project/:

```sh
node scripts/embed-web.cjs
node --test tests/web.test.cjs
python3 -m unittest discover -s tests -p 'test_*.py'
node tests/browser/verify.cjs
```

Browser tests need Node.js 22+ and Edge, or Chromium set through BROWSER_PATH.

With Xcode and an iOS Simulator on macOS:

```sh
python3 scripts/test-ios.py --video tests/ios/fixture.mp4
python3 scripts/test-ios.py --video tests/ios/fixture.mp4 --injected --output dist/ios-injected.json
python3 scripts/test-ios.py --video tests/ios/fixture.mp4 --injected --manual --output dist/ios-injected-manual.json
```

Actions checks production Settings, native playback, injected hooks and manual mode. UIKit, AVPlayer and WebKit are real; SDK callbacks and rate rejection are mocked. Browser checks cover media, timers, playables, frames, controls and animations.

Package checks cover layout, architectures, dependencies and minimum iOS. Release reports identify the tested commit.

On a rootless iPhone running Subway Surfers, Unity automatic closing and reward payouts passed. New Google and Mintegral completion paths still need live verification. Moloco auto-close is unsupported. Simulator results do not prove other games or server reward flows.
