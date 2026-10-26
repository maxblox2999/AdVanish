# AdVanish 0.2.0

Fixes the six beta2 audit findings: early closing, repeat-press closing, multi-frame actions, ambiguous media selection, stale creative actions and permanently blocked retries.

Manual requests now discover and validate media before authorizing one target. Ambiguous, incomplete or changed targets are left alone. Generic MRAID closing and SDK Skip activation are removed. AppLovin Close requires actual video-end observation, its SDK video-completion signal and no remaining media candidates.

Verification: 56 automated web tests and eleven real Edge media/frame cases passed. Both rootless and rootful packages are built from the same source commit through public Actions; complete source and SHA-256 checksums are included. See AUDIT.md and VALIDATION.md for scope and remaining checks.

Targets iOS 15-18 with arm64/arm64e builds. iOS 26 is experimental with a low chance of working. A compatible jailbreak and tweak loader are required.

This release has not been tested on a physical iPhone. Actual SDK rewards, in-game credit and crash-free device operation are not confirmed. It does not fabricate reward callbacks, and seeking/completion signals cannot guarantee a server-side reward.
