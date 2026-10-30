# Tests

Run from `project/`:

```sh
node scripts/embed-web.cjs
node --test tests/web.test.cjs
python3 -m unittest discover -s tests -p 'test_*.py'
node tests/browser/verify.cjs
```

The browser runner needs Node.js 22+ and Edge, or a Chromium executable set in `BROWSER_PATH`.

On macOS with Xcode and an iOS Simulator:

```sh
python3 scripts/test-ios.py --video tests/ios/fixture.mp4
python3 scripts/test-ios.py --video tests/ios/fixture.mp4 --injected --output dist/ios-injected.json
python3 scripts/test-ios.py --video tests/ios/fixture.mp4 --injected --manual --output dist/ios-injected-manual.json
```

Actions builds and inspects each package. Simulator fixtures exercise production hooks with real UIKit, AVPlayer and WebKit; SDK events and rejected-rate behavior are mocked. Browser fixtures cover video, playable timing, frames, controls, animations and cleanup. Package checks cover layout, architecture, loader dependencies and minimum iOS.

Release validation records the exact source commit and test results. These checks do not verify physical jailbreak loaders, arbitrary downloaded creatives, signed-device injection or actual game rewards. Build signatures are ad-hoc.

Settings has a separate simulator fixture that opens the production root and app pages against Apple's real Preferences.framework. It covers reentrant title construction, navigation, mutable row caching and rejected private getters. The linker stub declares only system symbols; the runtime test requires the real system framework. Physical PreferenceLoader loading remains unverified.
