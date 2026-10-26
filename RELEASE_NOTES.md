# AdVanish 0.2.1

Removes automatic AppLovin Close activation. The SDK schedules reward reporting separately from video completion, so an ended video cannot establish that closing is safe for a pending reward. After seeking, wait for the app's countdown or reward and use its own Close button.

Fixes silently ignored web seeks being reported as successful and leaving loops disabled. Rejected seeks now report failure and restore looping; bounded explicit retry remains available. Asynchronous seeks remain supported.

Verification: 58 automated web tests and twelve real Edge media/frame cases passed. Public Actions builds rootless/rootful packages and runs a native UIKit/AVPlayer simulator fixture with a mock SDK. Complete source and SHA-256 checksums are included. See AUDIT.md and VALIDATION.md for scope and remaining checks.

Targets iOS 15-18 with arm64/arm64e builds. iOS 26 is experimental with a low chance of working. A compatible jailbreak and tweak loader are required.

This release has not been tested on a physical iPhone. Actual SDK rewards, in-game credit and crash-free device operation are not confirmed. It does not fabricate reward callbacks, and seeking/completion signals cannot guarantee a server-side reward.
