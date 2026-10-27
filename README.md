<div align="center">

# AdVanish

16x ad fast-forwarding for iOS.

[![Build](https://github.com/maxblox2999/AdVanish/actions/workflows/build.yml/badge.svg)](https://github.com/maxblox2999/AdVanish/actions)
[![Test release](https://img.shields.io/github/v/release/maxblox2999/AdVanish?include_prereleases&style=flat-square&color=8957e5)](https://github.com/maxblox2999/AdVanish/releases)
![iOS target](https://img.shields.io/badge/iOS-15--18_target-333333?style=flat-square&logo=apple)

**[Download](https://github.com/maxblox2999/AdVanish/releases) · [Build your own](BUILD.md)**

</div>

## Use

**Jailbreak:** install the rootless or rootful package, enable an app in **Settings → AdVanish** and reopen it.

**Jailed:** inject the framework into an authorized decrypted IPA, then re-sign it. [Instructions](BUILD.md#ipa-injection).

Detected ads use **16x video and gameplay timing**. The floating **Fast-forward ad** button uses the same system. Drag it to move it; press only during an ad.

Supported playable controls receive automatic input. Closing waits for supported SDK completion signals. Rewards and server validation stay with the app.

## Support

Rootless, rootful and jailed injection. Targets **iOS 15–18**. **iOS 26 is experimental, with a low chance of working.**

Test release. Unknown playables may still need input. Real-game rewards and signed-device injection are not yet verified. [Support](docs/SUPPORT.md) · [Tests](docs/VALIDATION.md).

---

[Tests](docs/VALIDATION.md) · [Changes](docs/AUDIT.md) · [Credits](NOTICE.md) · [GPLv3](LICENSE)
