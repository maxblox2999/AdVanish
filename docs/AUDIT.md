# Code audit

## 0.3.0: audit before implementation

Baseline: `d3fa3fb990413c4ef006add99ba82c982c240316`. Reviewed native discovery, rate ownership, WebKit injection, frame messages, preferences, all build scripts, packaging, fixtures and documentation before changing executable code. Baseline checks: 71 Node tests; the prior build also passed 20 browser and 13 iOS Simulator checks.

| Finding | Effect | Required change |
| --- | --- | --- |
| `ManualSkip` disables the video, timer and clock flags in the constructor and Settings | The button and automatic speed cannot coexist | Keep the key as button visibility only |
| Manual paths hardcode 2x while the automatic path has a separate multiplier | Conflicting rates and cleanup ownership | Share the 16x target and protect internal rate restoration from hook recursion |
| Interactive creatives receive no generated input | Faster time cannot satisfy gameplay requirements | Bounded interaction only for recognizable controls; unknown canvas games remain unsupported |
| Animation-frame timestamps use native time | Some canvas games ignore accelerated clocks | Keep timestamps consistent with the existing virtual clock |
| Video-ended is separate from reward eligibility | Early Close can destroy a pending reward | Observe real SDK callbacks, preserve their arguments and wait for an eligible SDK Close |
| Legacy SDK stubs disable readiness, initialization and callbacks | Rewarded ads may never load or complete | Remove this mode; retain detection, speed and useful jailbreak compatibility hooks |
| Jailed branch still imports Substrate and has no release target | An injected binary cannot initialize independently | Use runtime-only hooks, sandbox configuration and a separately checked framework |
| Native fixture compiles helpers but not the hook constructor | Passing it does not prove injected startup | Add a fixture that loads the actual compiled hook library |

These are source and fixture findings, not physical-device results. No real-game reward has been verified. The seven supplied IPA analyses remain in [ANALYSIS.md](ANALYSIS.md).

### SDK boundaries

- [Google](https://developers.google.com/admob/ios/rewarded): the SDK invokes the supplied reward handler. Dismissal and reward are separate events, with mediation-dependent ordering.
- [MAX](https://support.applovin.com/en/max/ios/ad-formats/rewarded-ads): `didRewardUserForAd:withReward:` reports the reward. A video-ended event is insufficient.
- [LevelPlay](https://docs.unity.com/en-us/grow/levelplay/sdk/ios/rewarded-ads-integration): reward and close callbacks are separate. A callback received after closing cannot authorize an earlier dismissal.
- [Unity playables](https://docs.unity.com/en-us/user-acquisition/creatives/specifications/playable): MRAID controls viewability and store navigation; the SDK controls Close eligibility. It has no universal game-solving API.
- [AppLovin playables](https://support.applovin.com/en/max/demand-partners/demand-side-platforms/applovin-ortb-specification/creative-types): the playable timer starts after interaction. Generated DOM events may be rejected where a trusted physical touch is required.

Client callbacks do not replace [server-side verification](https://developers.google.com/admob/ios/ssv). The tweak must not call reward handlers, invent completion events, force controller dismissal or disable server validation.

## 0.2.2

- Fixed manual 2× playback continuing after a native video is hidden, detached, moved to another window or left in an inactive scene.
- Web playback now restores its original rate when hidden, removed, covered or paused. Paused videos stay paused.
- DOM cleanup batches mutations into one check per 250 ms while needed. It does not continuously poll in manual mode.
- The browser runner activates its test tab and removes stale results before starting.
- Shortened the README and Settings text. Detailed notes are under `docs/`.

## 0.2.1

Replaced manual end jumps with 2× playback after reports of black screens and failed rewards. Removed automatic SDK Close activation. Added transparent overlays, typed player getters and native simulator checks.

## Verification limits

Browser and simulator checks exercise playback, selection, cleanup and completion. The native fixture uses a mock SDK. These checks do not prove jailbreak injection, real SDK behavior or final game rewards. Physical-device testing is pending.

[Run the tests](VALIDATION.md) · [Decompilation findings](ANALYSIS.md)
