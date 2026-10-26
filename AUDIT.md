# Release audit: 0.2.0

The beta2 audit found six material problems. This release changes the action boundary instead of adding more SDK names.

| Finding | Repair |
| --- | --- |
| Close/Skip before completion | No generic MRAID close or SDK Skip activation. AppLovin Close requires an observed item-end event, its SDK video-completion signal, unchanged item/creative and zero remaining media candidates. |
| Repeat press could close unfinished video | A request never promotes an attempted seek to a completed ad. Unfinished, seeking and unsupported media prevent empty-document fallback. |
| Different frames could act simultaneously | Frame discovery and validation are read-only. One single-use token authorizes one selected target. |
| Local media could hide an iframe ad, or all videos could seek | Local and framed candidates are counted together; ambiguous selection performs no action. Native players and separate WKWebViews also share the same selection boundary. |
| A delayed response could close a new creative | Tokens snapshot element/source/frame identities, expire after five seconds, and validate recursively before action. Native requests freeze their item/creative and recheck current player/webview sets. |
| Failed seeks blocked all manual retries | New explicit requests can retry, bounded to three attempts per source/item. There is no automatic seek retry loop. |

## Additional native review

The combined source was reviewed again for malformed web results, stale callbacks, weak captures, new or removed media views, multiple scenes, method signatures and incomplete scans. Repairs from that review reject partial discovery, recheck singleton ownership during native readiness waits, disable those waits when web snapshots exist, and run the completion-gated close only after full zero-candidate discovery/validation.

A further manual-selection review found video hidden behind non-media foreground content. Manual discovery now samples DOM hit targets for both video and frame elements; covered targets stop the request. Three new regressions and two additional real-browser cases cover opaque overlays and covering iframes.

Web results are checked for dictionary/number/string types, finite bounded integers and bounded token lengths before native dispatch. SDK getters check argument counts and return encodings before typed dispatch; returned views, players and controls are checked at runtime. Unknown APIs, exceptions in optional SDK getters and failed validation stop the request.

## Verification performed

- 56 Node VM regression tests cover the shared web engine, including all six beta2 audit scenarios and the earlier timer/clock/media behavior.
- Eleven real Microsoft Edge 156.0.4314.42 cases exercised actual finite-video seeking and natural completion, cross-origin frames, ambiguity, stale local/child snapshots, looping media, token single use and a sibling bridge that must never close. No JavaScript errors or unhandled rejections were recorded.
- The browser fixture video was generated locally: H264, 160x90, 15fps, 12 seconds, no audio. No game binaries, proprietary media or private data are distributed.
- Both package variants must pass the public Actions build and static package checks before publication. Build artifacts record their exact commit and toolchain versions.

The browser-tested production script has SHA-256 `6d83c1ab6420adbce9d776a095273deb69f828a3d1e8f0118a776b23c52f3f8d`.

## Limits

The audit did not establish a remaining definite new native crash path. That is a source-review result, not a claim that the tweak cannot crash. No physical iPhone has run this release during verification. UIKit, iOS WebKit, injection, private SDK behavior, real ad dismissal, reward callbacks and final in-game credit still require device testing. Chromium fixtures cannot prove those outcomes.

Video seeking, an observed video end and an SDK video-completion flag do not establish every server-side reward condition. The tweak does not fabricate reward/completion callbacks. Unsupported or ambiguous ads can remain on screen. iOS 15-18 are deployment targets; iOS 26 remains experimental with a low chance of working until tested on a compatible jailbreak.
