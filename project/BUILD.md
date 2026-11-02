# Build

Fork the repository, enable Actions and run **Build** on `main`. Artifacts contain rootless, rootful, RootHide, jailed and full-source builds.

## macOS

Requires Xcode, Node.js 18+ and Python 3.9+. Run from `project/`:

```sh
brew install make ldid dpkg node python
export PATH="$(brew --prefix make)/libexec/gnubin:$PATH"
bash scripts/setup-theos.sh
export THEOS="$PWD/.theos-tools/theos"
bash scripts/build.sh rootless
bash scripts/build.sh rootful
bash scripts/build.sh jailed
```

RootHide uses its own pinned Theos checkout:

```sh
bash scripts/setup-theos.sh .theos-tools-roothide roothide
export THEOS="$PWD/.theos-tools-roothide/theos"
bash scripts/build.sh roothide
```

Outputs: `dist/<variant>/`. Verify its `SHA256SUMS`. [Dependency pins](build/dependencies.env) · [Tests](docs/VALIDATION.md).

## IPA injection

Extract the jailed ZIP and run:

```sh
python3 inject-ipa.py Game.ipa --framework AdVanish.framework --output Game-AdVanish-unsigned.ipa
python3 sign-ipa.py Game-AdVanish-unsigned.ipa --output Game-AdVanish-signed.ipa --identity "Apple Development: Your Name (TEAMID)" --profile Game.mobileprovision
```

The injector keeps the original IPA and accepts authorized decrypted, thin arm64 executables with enough header padding. Encrypted, fat, arm64e, duplicate and unsafe archives are rejected. The optional macOS signer handles one app with a matching profile; extensions need another signing tool.

Optional `--config AdVanish.plist` accepts boolean keys: `Enabled`, `AutomaticAds`, `ManualSkip`, `SpeedUpVideo`, `CompressTimers`, `AccelerateClock`, `ForceInline`, `AutoInteract`, `AutoDismiss`, `BlockRedirects`. The app's `NSUserDefaults` dictionary `AdVanish` overrides them. `AutomaticAds=false` requires the button and disables automatic input and Close.

Hooks use Logos. Every build needs the pinned Theos checkout. Jailbreak packages use the MobileSubstrate generator; jailed builds use the internal generator and need no Substrate.
