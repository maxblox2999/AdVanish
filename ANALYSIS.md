# Detection findings


This was a focused review of controller, media-owner and close/skip paths. It did not recover each game's complete source, execute the games, or verify device behavior. Proprietary binaries and pseudocode remain local and are not build inputs.

## Findings used in this change

- The original native context gate recognized GADFullScreenAdViewController and MAFullscreenAdViewController. The latter was absent from the inspected class definitions, while actual AppLovin video-controller implementations were present in every sample. Its one-time context hooks also missed classes loaded later.
- In every sample, ALBaseVideoViewController.avPlayer follows videoPlayer -> videoView -> player. The adapter validates object-returning, zero-argument getters, checks UIView/AVPlayer runtime types, and requires a visible owned video view. The generic path reads visible AVPlayerLayer.player relationships.
- AppLovin handleSkipVideo has SDK-dependent dismiss/postitial branches. Seeking a video or pressing a real control does not establish that an ad was dismissed or a reward was granted.
- Unity controller callbacks include indirect Swift/protocol calls. These establish controller lifecycle paths, but do not resolve every web/player relationship. Unity uses descendant media discovery; no guessed Swift getter or close handler is invoked.

## Sample identity

Each hash identifies the exact native image inspected, not the whole IPA. Addresses are unslid virtual addresses from that image. Main denotes the main executable; UnityFramework denotes the framework carrying the embedded SDK code.

| Sample | Image | SHA-256 | ALBase avPlayer | GAD closeButton |
| --- | --- | --- | --- | --- |

## Runtime limits

Controller names are stronger ownership signals for the reviewed SDKs, not a requirement for the manual fallback. Generic discovery cannot prove that visible media is advertising. Media hidden by unusual layer/view arrangements, custom renderers, inaccessible cross-origin frames, live streams, close gates and server-side reward rules can remain unsupported. Visibility sampling and UIKit ownership require device testing.

The old global ad-depth counter and globally most-recent player selection were removed. Each manual request stays in its originating scene/surface, freezes its native item, checks ownership again during retries, and waits for bounded web-frame acknowledgments before falling through. Unknown frame results stop fallback instead of treating a timeout as an empty ad.
