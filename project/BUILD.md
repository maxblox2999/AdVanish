# Build

Fork the repository, enable Actions, then run Build on main. Checks run once before packaging: rootless, jailed, rootful, then RootHide. Each package is uploaded as it finishes.

Publishing requires all checks and packages to pass. An existing release is kept; bump the package version to publish another. Select the macOS runner under Run workflow. An idle push build can retry once on Intel before any macOS job has finished.

## macOS

Requires Xcode, Node.js 22+ and Python 3.9+. Run from project/:

```sh
brew install make ldid dpkg node python
export PATH="$(brew --prefix make)/libexec/gnubin:$PATH"
bash scripts/setup-theos.sh
export THEOS="$PWD/.theos-tools/theos"
bash scripts/build.sh rootless
bash scripts/build.sh rootful
bash scripts/build.sh jailed
```

RootHide needs its separate toolchain:

```sh
bash scripts/setup-theos.sh .theos-tools-roothide roothide
export THEOS="$PWD/.theos-tools-roothide/theos"
bash scripts/build.sh roothide
```

Packages and SHA256SUMS are in dist/<variant>/. Builds use the [pinned dependencies](build/dependencies.env).

## IPA injection

Extract the jailed ZIP:

```sh
python3 inject-ipa.py Game.ipa --framework AdVanish.framework --output Game-AdVanish-unsigned.ipa
python3 sign-ipa.py Game-AdVanish-unsigned.ipa --output Game-AdVanish-signed.ipa --identity "Apple Development: Your Name (TEAMID)" --profile Game.mobileprovision
```

The injector preserves the input IPA. It requires an authorized decrypted, thin arm64 executable with header padding. Encrypted, fat, arm64e and unsafe archives are rejected. The macOS signer handles one app with a matching profile; extensions need a separate signing tool.

Optional --config AdVanish.plist accepts booleans: Enabled, AutomaticAds, ManualSkip, SpeedUpVideo, CompressTimers, AccelerateClock, ForceInline, AutoInteract, AutoDismiss, BlockRedirects, HideAppStore and BlockBanners. The app's AdVanish NSUserDefaults dictionary overrides them. AutomaticAds=false enables button-only acceleration and disables automatic input and closing.

Hooks use Logos. Jailbreak builds use the MobileSubstrate generator; injected frameworks use the internal generator and do not require Substrate.
