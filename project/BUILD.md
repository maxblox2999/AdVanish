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

The injector preserves the original IPA and accepts authorized decrypted, thin arm64 executables with sufficient header padding. Encrypted, fat, arm64e, duplicate and unsafe archives are rejected. The optional macOS signer supports a single app with a matching profile; extensions require another signing tool. Build signatures are ad-hoc; signed-device installation remains unverified.

Optional `--config AdVanish.plist` accepts boolean keys: `Enabled`, `AutomaticAds`, `ManualSkip`, `SpeedUpVideo`, `CompressTimers`, `AccelerateClock`, `ForceInline`, `SpeedNativeVideo`, `AutoInteract`, `AutoDismiss`, `BlockRedirects`. The app's `NSUserDefaults` dictionary `AdVanish` can override them. `AutomaticAds=false` requires the button; it disables automatic input and Close.

[Cyanide compatibility](docs/CYANIDE.md) · [Ad types](docs/AD_TYPES.md).
