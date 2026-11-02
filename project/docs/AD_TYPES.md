# Ad types

Automatic mode applies 16x playback and web timing throughout each enabled app, including non-ad media. Ad detection still controls generated interaction and completion.

Detection, acceleration, completion and rewards are separate. Recognizing an ad does not mean its creative can be completed automatically. No supplied game has passed a physical-device reward test here.

| Ad path | Acceleration | Automatic Close |
| --- | --- | --- |
| AVPlayer video in an enabled app | 16x first; 8x/4x/2x fallback after rejection, no seek | Supported Google ordinary-video completion or a matching genuine rewarded event |
| HTML video, including nested frames | 16x automatic playback; manual requests retain surface selection | Requires a supported native SDK completion path |
| MRAID playable using JS timers or elapsed time | Timer, clock and animation-frame acceleration | No universal playable-complete callback; native SDK eligibility is still required |
| CSS and Web Animations in an enabled app | 16x running-animation rate relative to its base; pause and cleanup preserved | Animation end does not fabricate an SDK reward |
| Playable with explicit gameplay controls | Bounded tap/swipe assistance in automatic mode; native-owned non-MRAID surfaces are included | Same SDK completion requirements |
| Playable with decorative video | Manual timing can run while looped, ended or paused media remains unchanged | Same SDK completion requirements |
| One SDK-owned native/web pair | One validated manual request can accelerate both parts | Same SDK completion requirements |
| Canvas/WebGL logic advancing once per rendered frame | Time-based code may accelerate; fixed-step code may not | No generic solver or invented completion event |
| Native static/end-card countdown | NSTimer countdowns accelerate while an ad surface is active | Server reward checks and Close eligibility are unchanged |
| Worker, remote or trusted-touch-only creative | Not verified; worker timing is not hooked | May require actual interaction |
| Banner, native-feed or live media | No generic fullscreen skip | No automatic removal adapter |
| Native video followed by an end card | Video can accelerate; the end-card phase has its own requirements | Video end alone cannot close a mixed or rewarded session |

The manual button selects an eligible video or a recognized playable timing surface. It does not solve arbitrary games, grant rewards or force controller dismissal. Ambiguous surfaces, inaccessible frames, stale sessions and rejected playback rates abstain rather than selecting unrelated media.

Manual timing freezes its primary playable node. Replacing that node requires a new press; same-node countdown updates keep their speed. [Completion adapters](SUPPORT.md) · [Test scope](VALIDATION.md).
