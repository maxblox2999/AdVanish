# Build AdVanish

## GitHub Actions

1. Fork the repository.
2. Open your fork's **Actions** tab and enable workflows if GitHub asks.
3. Select **Build**, then **Run workflow** on `main`.
4. Download `advanish-rootless-<commit>`, `advanish-rootful-<commit>` and `advanish-source-<commit>` from the completed run.

The first two artifacts contain a `.deb`, SHA256SUMS, package inspection results and toolchain details. The source artifact contains this entire source tree, including tests, build scripts, dependency pins and workflow. It also records its commit in SOURCE_COMMIT. No Apple signing credentials, game IPAs or repository secrets are required.

## Local build on macOS

Install Xcode and its command-line tools. Use the Xcode license flow if prompted by `xcodebuild`; the scripts do not accept it for you. Then install GNU make, ldid and dpkg, and ensure Node.js 18+ and Python 3.9+ are available:

```sh
brew install make ldid dpkg node python
export PATH="$(brew --prefix make)/libexec/gnubin:$PATH"
bash scripts/setup-theos.sh
export THEOS="$PWD/.theos-tools/theos"
bash scripts/build.sh rootless
bash scripts/build.sh rootful
```

Packages are written to `dist/rootless/` and `dist/rootful/`. The build script cleans intermediate files when switching schemes. Both variants compile the tweak and Settings panel for arm64 and arm64e with an iOS 15 deployment minimum. Rootless packages install under `/var/jb`; rootful packages use `/Library`.

Verify an artifact after downloading:

```sh
cd dist/rootless
shasum -a 256 -c SHA256SUMS
```

Use the package matching the device's actual jailbreak layout. The package replaces older AdSpeed installations and preserves the original preference domain. This project does not install or change a jailbreak.

## Dependencies and repeatability

`build/dependencies.env` pins Theos, its selected submodule revisions through Theos, and the patched iOS 16.5 SDK repository. Workflow actions are pinned to commit SHAs. The patched SDK includes the Preferences link stubs required for the Settings panel.

The hosted macOS image, Xcode and Homebrew packages can change. Their versions are recorded in each build-info.txt. These are reproducible build instructions; byte-for-byte identical packages across different toolchain versions are not promised.

The deployment minimum is not an upper OS limit. iOS 15–18 is the target range. iOS 26 is experimental with a low chance of working until tested against its actual jailbreak, UIKit, WebKit and Settings behavior.
