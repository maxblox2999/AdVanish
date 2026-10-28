# Build

## GitHub Actions

Fork this repository, enable Actions, then run **Build → Run workflow** on `main`.

Download the rootless, rootful, jailed and source artifacts from the completed run. No signing secrets or game IPAs are needed for builds. Source archives include `SOURCE_COMMIT`.

## macOS

Requires Xcode, its command-line tools, Node.js 18+ and Python 3.9+. Complete Xcode's setup before building. Run these commands from `project/`:

```sh
brew install make ldid dpkg node python
export PATH="$(brew --prefix make)/libexec/gnubin:$PATH"
bash scripts/setup-theos.sh
export THEOS="$PWD/.theos-tools/theos"
bash scripts/build.sh rootless
bash scripts/build.sh rootful
bash scripts/build.sh jailed
```

Packages, the jailed framework and checksums are written to `dist/<variant>/`.

```sh
cd dist/rootless
shasum -a 256 -c SHA256SUMS
```

Jailbreak packages contain arm64/arm64e builds with an iOS 15 minimum. Choose the package matching your jailbreak layout. Existing app enablement and feature preferences are retained. Acceleration targets 16x. **Automatic ads** controls automatic acceleration, input and dismissal; turn it off for button-only acceleration. Existing explicit manual-button preferences default to manual mode until you choose otherwise.

## IPA injection

The jailed artifact contains `AdVanish.framework` and Python helpers. It uses Objective-C runtime hooks and public system frameworks; it does not need Substrate, ElleKit, PreferenceLoader or a jailbreak.

Extract `AdVanish-jailed.zip`, then run from the artifact directory:

```sh
python3 inject-ipa.py Game.ipa --framework AdVanish.framework --output Game-AdVanish-unsigned.ipa
```

This prepares a new IPA and preserves the original, including executable permissions. The bundled injector currently accepts thin, plain arm64 executables. Use an authorized decrypted IPA. Encrypted executables, fat or arm64e executables, insufficient Mach-O header space, duplicate injection and unsafe archives are rejected. It does not decrypt App Store apps. A different injector may support more layouts, but those paths are not verified here.

Re-sign the prepared IPA with your signing tool. For a single app without extensions, the optional macOS helper uses an existing keychain identity and a provisioning profile for the exact bundle ID:

```sh
python3 sign-ipa.py Game-AdVanish-unsigned.ipa --output Game-AdVanish-signed.ipa \
  --identity "Apple Development: Your Name (TEAMID)" --profile Game.mobileprovision
```

Embedded libraries and frameworks are signed before the app. Apps with extensions or unsupported capabilities need a signing tool that handles their profiles. Build signatures are ad-hoc and cannot install on stock iOS by themselves. Signing and installation on a physical device remain unverified.

Jailed settings use `AdVanish.plist` in the app bundle, with optional overrides from the app's `NSUserDefaults` dictionary named `AdVanish`. They never read jailbreak preference paths. All features default on except force-inline and broad native-video acceleration. The same detection, speed and manual controls initialize inside the app.

Pass `--config AdVanish.plist` to the injector to embed a configuration. It accepts boolean keys `Enabled`, `AutomaticAds`, `ManualSkip`, `SpeedUpVideo`, `CompressTimers`, `AccelerateClock`, `ForceInline`, `SpeedNativeVideo`, `AutoInteract`, `AutoDismiss` and `BlockRedirects`. The speed target remains 16x. For example, this enables automatic behavior and hides the manual button:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>AutomaticAds</key><true/>
  <key>ManualSkip</key><false/>
</dict></plist>
```

Dependencies are pinned in [build/dependencies.env](build/dependencies.env). Each artifact records its toolchain in `build-info.txt`; different toolchains can produce different binary hashes.

Test runners and their limits: [docs/VALIDATION.md](docs/VALIDATION.md).
