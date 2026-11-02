# Tests

Run from project/:

```sh
node scripts/embed-web.cjs
node --test tests/web.test.cjs
python3 -m unittest discover -s tests -p 'test_*.py'
node tests/browser/verify.cjs
```

Browser tests need Node.js 22+ and Edge, or Chromium set through BROWSER_PATH.

On macOS, install Xcode and an iOS Simulator:

```sh
python3 scripts/test-ios.py --video tests/ios/fixture.mp4
python3 scripts/test-ios.py --video tests/ios/fixture.mp4 --injected --output dist/ios-injected.json
python3 scripts/test-ios.py --video tests/ios/fixture.mp4 --injected --manual --output dist/ios-injected-manual.json
```

Actions also runs the production Settings fixture. Simulator tests use real UIKit, AVPlayer and WebKit with mocked SDK events and rate rejection. Browser tests cover video, playable timing, frames, controls, animations and cleanup.

Package checks verify layout, architecture, dependencies and minimum iOS. Release reports record the tested source commit.

These checks do not establish real-game ad closing, reward payouts or physical-device compatibility.
