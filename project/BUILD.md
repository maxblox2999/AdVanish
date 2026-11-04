# Build

Fork the repository, enable Actions and run Build on main. Checks run first, then rootless, jailed, rootful and RootHide packages.

Publishing requires every check and package to pass. Bump project/control to publish a new version; existing downloads stay unchanged. Run workflow lets you choose the macOS runner. Idle push builds can retry once on Intel before any macOS job finishes.

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

The injector keeps the input IPA unchanged. It needs an authorized decrypted, thin arm64 executable with header padding. Encrypted, fat, arm64e and unsafe archives are rejected. The macOS signer supports one app and its frameworks with a matching profile; sign extensions separately.

--config AdVanish.plist accepts booleans: Enabled, AutomaticAds, ManualSkip, SpeedUpVideo, CompressTimers, AccelerateClock, ForceInline, AutoInteract, AutoDismiss, BlockRedirects, HideAppStore and BlockBanners. The app's AdVanish NSUserDefaults dictionary overrides the file. AutomaticAds=false enables button-only acceleration.

Hooks use Logos. Jailbreak builds use the MobileSubstrate generator; injected frameworks use the internal generator and do not require Substrate.
