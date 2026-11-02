<div align="center">

# AdVanish

80x ad fast-forwarding for iOS.

[![Build](https://github.com/maxblox2999/AdVanish/actions/workflows/build.yml/badge.svg)](https://github.com/maxblox2999/AdVanish/actions)
[![Test release](https://img.shields.io/github/v/release/maxblox2999/AdVanish?include_prereleases&style=flat-square&color=8957e5)](https://github.com/maxblox2999/AdVanish/releases)
![iOS target](https://img.shields.io/badge/iOS-15--18_target-333333?style=flat-square&logo=apple)

[Download](https://github.com/maxblox2999/AdVanish/releases) | [Build your own](project/BUILD.md)

</div>

## Use

Jailbreak: install the matching rootless, rootful or RootHide package. Apps are enabled by default; open Settings -> AdVanish to disable one.

Jailed: inject the framework into an authorized decrypted IPA, then re-sign it. [Instructions](project/BUILD.md#ipa-injection).

Automatic ads enables acceleration and completion. Turn it off for button-only acceleration. Targets 80x, falling back to a lower rate when a player rejects it.

Rewards and server validation stay with the app.

## Support

Compatibility: rootless, rootful, RootHide and jailed injection.
iOS versions: 15-18. iOS 26 is experimental.
Ad types: supports reward-based ads, including server-sided ones. Designed to be universal, but may not detect every ad type.

Known issue: long sessions can cause performance issues and slower ad completions. Reopen the app if that happens and report via an issue. The ad detection rate is high; if an ad is not skipped it is likely detected but not yet supported. Auto-completion is still a work in progress with limited coverage.

See [Ad types](project/docs/AD_TYPES.md) and [Tests](project/docs/VALIDATION.md).

Source, tests and build tools are in [project/](project/).

---

[maxblox2999](https://github.com/maxblox2999) | [Changes](project/docs/AUDIT.md) | [License](LICENSE)