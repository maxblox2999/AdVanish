# AdVanish 0.2.1

Addresses the reported black screen and failed reward after pressing Skip: the manual button now requests 2x playback instead of jumping to the video end. It is labelled Fast-forward ad. SDK countdowns stay unchanged; wait for the app's reward/countdown and use its own Close button. Actual game rewards still need device testing.

Removes automatic AppLovin Close activation, leaves looping web creatives unchanged, checks rejected speed changes and releases manual rates on media changes without resuming paused playback. The floating window and root view are explicitly transparent. Also fixes success reporting for ignored seeks in the legacy web engine.

Verification includes 67 automated web tests, sixteen real Edge media/frame cases and a native UIKit/AVPlayer simulator fixture with a mock SDK. Public Actions builds rootless/rootful packages. Complete source, test runners and SHA-256 checksums are included. See AUDIT.md and VALIDATION.md for scope and remaining checks.

Targets iOS 15-18 with arm64/arm64e builds. iOS 26 is experimental with a low chance of working. A compatible jailbreak and tweak loader are required.

This release has not been tested on a physical iPhone. Actual SDK rewards, in-game credit and crash-free device operation are not confirmed. It does not fabricate reward callbacks, and seeking/completion signals cannot guarantee a server-side reward.
