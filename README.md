<div align="center">

# AdVanish

80x ad fast-forwarding for iOS.

[![Build](https://github.com/maxblox2999/AdVanish/actions/workflows/build.yml/badge.svg)](https://github.com/maxblox2999/AdVanish/actions/workflows/build.yml)
[![Test release](https://img.shields.io/github/v/release/maxblox2999/AdVanish?include_prereleases&style=flat-square&color=8957e5)](https://github.com/maxblox2999/AdVanish/releases)
![iOS target](https://img.shields.io/badge/iOS-15--18_target-333333?style=flat-square&logo=apple)

[Download](https://github.com/maxblox2999/AdVanish/releases) | [Build](project/BUILD.md)

</div>

## Install

| Setup | Download |
| --- | --- |
| Rootless jailbreak | rootless.deb |
| Rootful jailbreak | rootful.deb |
| RootHide bootstrap | roothide.deb |
| IPA injection | jailed.zip, then inject and re-sign |

DEBs include arm64 and arm64e. Targets iOS 15-18; iOS 26 is experimental and has a low chance of working.

## Use

Open Settings -> AdVanish. Apps are enabled by default. Turn off Automatic ads for button-only acceleration. Reopen the game after changing settings.

Video and web timing target 80x, with lower-rate fallback. Automatic mode also speeds non-ad media in enabled apps. Google banner blocking is optional.

Automatic closing has limited coverage and is still unreliable in real games. Rewards require normal SDK completion and server validation. Simulator checks do not verify real-game rewards.

[Ad support](project/docs/AD_TYPES.md) | [Tests](project/docs/VALIDATION.md) | [Changes](project/docs/CHANGES.md)

[maxblox2999](https://github.com/maxblox2999) | [License](LICENSE)
