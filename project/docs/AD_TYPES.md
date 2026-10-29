# Ad types

Detection, acceleration, completion and rewards are separate. Recognizing an ad does not mean its creative can be completed automatically. No supplied game has passed a physical-device reward test here.

| Ad path | Acceleration | Automatic Close |
| --- | --- | --- |
| Visible owned AVPlayer video | 16x first; 8x/4x/2x fallback after rejection, no seek | Supported Google ordinary-video completion or a matching genuine rewarded event |
| HTML video, including nested frames | 16x playback on an authorized visible surface | Requires a supported native SDK completion path |
| MRAID playable using JS timers or elapsed time | Timer, clock and animation-frame acceleration | No universal playable-complete callback; native SDK eligibility is still required |
| CSS and Web Animations on a recognized ad surface | 16x running-animation rate relative to its base; pause and cleanup preserved | Animation end does not fabricate an SDK reward |
| Playable with explicit gameplay controls | Bounded tap/swipe assistance in automatic mode | Same SDK completion requirements |
| Playable with decorative video | Manual timing can run while looped, ended or paused media remains unchanged | Same SDK completion requirements |
| One SDK-owned native/web pair | One validated manual request can accelerate both parts | Same SDK completion requirements |
| Canvas/WebGL logic advancing once per rendered frame | Time-based code may accelerate; fixed-step code may not | No generic solver or invented completion event |
| Native static/end-card countdown | SDK timer is unchanged | No early Close or reward fabrication |
| Worker, remote or trusted-touch-only creative | Not verified; worker timing is not hooked | May require actual interaction |
| Banner, native-feed or live media | No generic fullscreen skip | No automatic removal adapter |
| Native video followed by an end card | Video can accelerate; the end-card phase has its own requirements | Video end alone cannot close a mixed or rewarded session |

The manual button selects an eligible video or a recognized playable timing surface. It does not solve arbitrary games, grant rewards or force controller dismissal. Ambiguous surfaces, inaccessible frames, stale sessions and rejected playback rates abstain rather than selecting unrelated media.

## Supplied samples

All seven IPA inventories and the retained selected native decompilations were reviewed. These framework versions are static metadata, not a claim that every network creative from them works.

| Sample | AppLovin | Other embedded framework metadata |
| --- | --- | --- |
| BlockBlast! | 13.6.3 | InMobi 11.3.0, Moloco 4.7.0, Meta Audience Network |
| SolarSmash | 13.6.3 | InMobi 11.3.0, Moloco 4.7.0, Meta Audience Network |
| WorldBox | 13.4.0 | InMobi 10.8.6, Meta Audience Network |
| Aquapark.io | 13.6.4 | InMobi 11.4.0, Moloco 4.8.0, Meta Audience Network |
| Subway Surf | 13.6.2 | InMobi 11.4.0, Moloco 4.8.1, Meta Audience Network |
| OfflineGames 2 | 13.6.4 | InMobi 11.4.1, Meta Audience Network |
| OfflineGames | 13.6.2 | InMobi 11.3.0, Moloco 4.6.1, Meta Audience Network |

Google and Unity SDK paths also occur in the inspected native method lists. An IPA contains SDK code and bundled resources; it does not contain every advertisement the SDK can later download. [Native findings and sample hashes](ANALYSIS.md) · [Completion adapters](SUPPORT.md) · [Test scope](VALIDATION.md).
