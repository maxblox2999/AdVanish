
<div align="center">

# AdVanish

Hate having ads shoved in your face? Got a jailbroken device? **AdVanish has you covered!**

Built for modern iOS versions, with support for different jailbreak types, plus a jailed build for devices without a jailbreak.

**Less waiting. Rights to have fun.**

[![Build](https://github.com/maxblox2999/AdVanish/actions/workflows/build.yml/badge.svg)](https://github.com/maxblox2999/AdVanish/actions)
[![Test release](https://img.shields.io/github/v/release/maxblox2999/AdVanish?include_prereleases&style=flat-square&color=8957e5)](https://github.com/maxblox2999/AdVanish/releases)
![iOS target](https://img.shields.io/badge/iOS-15--18_target-333333?style=flat-square&logo=apple)

**[Download](https://github.com/maxblox2999/AdVanish/releases) . [Build your own](project/BUILD.md)**

</div>

## Use

**Jailbreak:** Install the matching rootless, rootful, or RootHide package. Apps are enabled by default. Open **Settings Scroll all the way down AdVanish** to disable one.
If you are on iOS/iPadOS 18 or higher, **Settings General Scroll all the way down AdVanish**.

**Jailed:** Inject the framework into an authorized decrypted IPA, then re-sign it. See [Instructions](project/BUILD.md#ipa-injection).

**Automatic ads** enables acceleration and completion. Turn it off for button-only acceleration. Targets **80x**, falling back to a lower rate when a player rejects it.

Rewards and server validation stay with the app.

## Support

- **Compatibility:** Rootless, rootful, RootHide, and jailed injection.
- **iOS Versions:** iOS 15-18. *(iOS 26 is experimental)*
- **Ad Types:** Supports reward-based ads, including server-sided ones. Designed to be universal, but it may not detect every ad type.
  
> [!IMPORTANT]
> **AdVanish is still a new project**, so expect bugs, compatibility issues, and features that don't always work as intended. Some ads may not speed up, skip, or close properly. If you run into any problems, please open an issue and explain what happened.
> > Ad skipping is still unfinished and has a lot of issues. However, ad speeding should work with nearly every ad. If speeding doesn't work in an app, please open an issue and mention which app you were using. Max will manually review the app to investigate the problem.
>
> The ad detection rate is very high. If an ad doesn't get skipped, it's most likely being detected but isn't supported yet. If you know how to improve support or compatibility, feel free to open an issue explaining how.
>
> **Note:** Auto-completion is still a work in progress and currently has limited coverage over ad providers.
> I am also aware that certain types of ads this still does not work with speeding the ad, likely due to the counter and ad being on a seperate thing i might make the entire app speed instead of only a ad when it detects a ad. 


> [!NOTE]
> **AdVanish is NOT an ad blocker.** It speeds up ads and automatically closes them when possible.
>  It only works with iOS/iPadOS apps, not browsers like Safari.
>
> YouTube, Spotify, Roblox etc etc.. are NOT supported and never will be.
> AdVanish is only meant for IPAs and apps you have permission to test.
> It will not support bypassing ads in any non-allowed apps.


See [Ad Types](project/docs/AD_TYPES.md) and [Tests](project/docs/VALIDATION.md).

Source code, tests, and build tools are located in [`project/`](project/).

---

> [!CAUTION]
> The owner is NOT responsible for how AdVanish is used and it is only meant to be used in apps you are authorized to use it in to fix their security.
> This project contains the use for ai for testing the tweak and applying bug fixes. 
[maxblox2999](https://github.com/maxblox2999)  [Changes](project/docs/CHANGES.md)  [License](LICENSE)
