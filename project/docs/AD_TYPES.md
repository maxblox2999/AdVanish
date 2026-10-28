# Ad types

Detection, acceleration, completion and rewards are separate. Recognizing an ad does not mean its creative can be completed automatically. No supplied game has passed a physical-device reward test here.

| Ad path | Acceleration | Automatic Close |
| --- | --- | --- |
| Visible owned AVPlayer video | Existing 16x playback; no seek | Supported Google ordinary-video completion or a matching genuine rewarded event |
| HTML video, including nested frames | 16x playback on an authorized visible surface | Requires a supported native SDK completion path |
| MRAID playable using JS timers or elapsed time | Timer, clock and animation-frame acceleration | No universal playable-complete callback; native SDK eligibility is still required |
| CSS and Web Animations on a recognized ad surface | 16x running-animation rate relative to its base; pause and cleanup preserved | Animation end does not fabricate an SDK reward |
| Playable with explicit gameplay controls | Bounded tap/swipe assistance in automatic mode | Same SDK completion requirements |
| Canvas/WebGL logic advancing once per rendered frame | Time-based code may accelerate; fixed-step code may not | No generic solver or invented completion event |
| Native static/end-card countdown | SDK timer is unchanged | No early Close or reward fabrication |
| Worker, remote or trusted-touch-only creative | Not verified; worker timing is not hooked | May require actual interaction |
| Banner, native-feed or live media | No generic fullscreen skip | No automatic removal adapter |
| Native video followed by an end card | Video can accelerate; the end-card phase has its own requirements | Video end alone cannot close a mixed or rewarded session |

The manual button selects an eligible video or a recognized playable timing surface. It does not solve arbitrary games, grant rewards or force controller dismissal. Ambiguous surfaces, inaccessible frames, stale sessions and rejected playback rates abstain rather than selecting unrelated media.



| Sample | AppLovin | Other embedded framework metadata |
| --- | --- | --- |

