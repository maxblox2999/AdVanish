# Detection findings

The AdSpeed dylib and selected ad-related native methods from all seven supplied IPAs were decompiled with direct Ghidra 12.1.4. REA supplied package inventories; its Windows native provider could not analyze these Mach-O images. Direct Ghidra output is supplemental evidence, not a canonical REA decompilation record.

This was a focused review of controller, media-owner and close/skip paths. It did not recover each game's complete source, execute the games, or verify device behavior. Proprietary binaries and pseudocode remain local and are not build inputs.

## Findings used in this change

- The original native context gate recognized GADFullScreenAdViewController and MAFullscreenAdViewController. The latter was absent from the inspected class definitions, while actual AppLovin video-controller implementations were present in every sample. Its one-time context hooks also missed classes loaded later.
- In every sample, ALBaseVideoViewController.avPlayer follows videoPlayer -> videoView -> player. The adapter validates object-returning, zero-argument getters, checks UIView/AVPlayer runtime types, and requires a visible owned video view. The generic path reads visible AVPlayerLayer.player relationships.
- Decompiled GAD initialization mounts the ad view under its controller and creates its close control. GAD closeButton and AppLovin closeButton/skipButton getters expose SDK-owned objects. The adapter activates only actual UIControls that are visible, enabled, interactive and hit-testable. It does not call private dismiss/skip handlers directly.
- AppLovin handleSkipVideo has SDK-dependent dismiss/postitial branches. Seeking a video or pressing a real control does not establish that an ad was dismissed or a reward was granted.
- Unity controller callbacks include indirect Swift/protocol calls. These establish controller lifecycle paths, but do not resolve every web/player relationship. Unity uses descendant media discovery; no guessed Swift getter or close handler is invoked.

## Sample identity

Each hash identifies the exact native image inspected, not the whole IPA. Addresses are unslid virtual addresses from that image. Main denotes the main executable; UnityFramework denotes the framework carrying the embedded SDK code.

| Sample | Image | SHA-256 | ALBase avPlayer | GAD closeButton |
| --- | --- | --- | --- | --- |
| BlockBlast!.ipa | main | `720953d8e9fe769cb56b1bcbe9fe544835ac6ed70d7f994d299a3f815a9b8ab1` | - | 0x10228505c |
| BlockBlast!.ipa | AppLovinSDK.framework | `9c85e8e9c447cdccc305fbba3784d85af5070b9c686c1296eca92f40bf2422c8` | 0x24a0c | - |
| SolarSmash.ipa | AppLovinSDK.framework | `faff5f1c9240d24c881f7f70fe130b548c93b3714473d77d6916c22a17854d0f` | 0x24a0c | - |
| SolarSmash.ipa | UnityFramework.framework | `66cb2657171f504d2ecf8b2e4e13097d01b2116eb892953ccae5b6b58086c68b` | - | 0xb4cdbc |
| WorldBox.ipa | AppLovinSDK.framework | `bc95b2c217cf2347026820e3954129ad8a81cf6793f6d3175b025f38c7892bf4` | 0x251dc | - |
| WorldBox.ipa | UnityFramework.framework | `053c66651b7d2f2775cfac14895da12a655894662a60c92d479bac1f48042beb` | - | 0x2afce0 |
| Aquapark.io.ipa | AppLovinSDK.framework | `3fbc7e9795cbede8c0b8280fc7eaaec99113c16b8889c92e4882bc83ea986058` | 0x24b00 | - |
| Aquapark.io.ipa | UnityFramework.framework | `d52ab4f30f2065ef3d85547d2c29bb2b9d0d8cfa2d8e1809c58fcbd36540dae7` | - | 0xc25ae8 |
| SubwaySurf.ipa | AppLovinSDK.framework | `316a3f400f2805eb48941f4afef89e35a0e6dd963cfaf8b51aaf78d03b36fc21` | 0x288b8 | - |
| SubwaySurf.ipa | UnityFramework.framework | `e9acffbe081e77aa316f358ec5ca15fb83dab49e1a144767f83f02f3e33cd9ad` | - | 0xa69b34 |
| OfflineGames 2.ipa | main | `a1a7adaffaf740d23ed218639c03f8e058769ff8db5559a9c72ec55bf246f27a` | - | 0x1003805ac |
| OfflineGames 2.ipa | AppLovinSDK.framework | `d3333d195ceda92cf399e5eb91b5472bc2209b98c62d35e93476f4dc544fdfeb` | 0x24b00 | - |
| OfflineGames.ipa | AppLovinSDK.framework | `2a5889a1f02cb3de2138bdfee55e97cdb7e3b9a11dcf0d9a35424e248bb14d2c` | 0x288b8 | - |
| OfflineGames.ipa | UnityFramework.framework | `2f88f3b354baeab03d5ee8543e0f92b0d9b9ef4502846a989aa5998cda2a7730` | - | 0xa3052c |

## Runtime limits

Controller names are stronger ownership signals for the reviewed SDKs, not a requirement for the manual fallback. Generic discovery cannot prove that visible media is advertising. Media hidden by unusual layer/view arrangements, custom renderers, inaccessible cross-origin frames, live streams, close gates and server-side reward rules can remain unsupported. Visibility sampling and UIKit ownership require device testing.

The old global ad-depth counter and globally most-recent player selection were removed. Each manual request stays in its originating scene/surface, freezes its native item, checks ownership again during retries, and waits for bounded web-frame acknowledgments before falling through. Unknown frame results stop fallback instead of treating a timeout as an empty ad.
