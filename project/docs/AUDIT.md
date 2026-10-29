# Code audit

## 0.3.1: AppLovin X

The supplied SDK's `ALExitButton` is a `UIView`, not a `UIControl`. The 0.3.0 Close adapter rejected it even after a matching reward. Its reviewed tap-registration helper attaches a `UITapGestureRecognizer` with the SDK's target and action.

The new adapter records that actual registration for the controller's own Close view. It can replay the registered action only after a genuine matching reward, while the creative, owner, view and enabled gesture still match. It does not guess a private close selector, force controller dismissal or create a reward callback. Manual-only mode keeps automatic Close disabled.

## Follow-up: reported playable, manual and Close failures

Reviewed native discovery, rate ownership, manual selection, reward sessions, WebKit timing and frame messages, preferences, injection/signing, build scripts, Actions, tests and retained evidence for all seven supplied IPAs before changing them. The existing detection families and 16x video implementation are preserved.

| Confirmed issue | Effect | Correction |
| --- | --- | --- |
| `ManualSkip` only controlled button visibility | Automatic speed, input and Close remained enabled | Separate `AutomaticAds` policy; explicit old manual preferences default to manual mode |
| An auto-detected MRAID parent sent nullable context to its child instead of its positive recognition | A playable inside the child ran at normal speed without its own MRAID bridge | Propagate recognized, exposed parent context and revoke it when covered |
| CSS and Web Animations kept their native playback rate | DOM-based playable animation stayed at normal speed despite accelerated JS clocks | Bounded running-animation rate leases with pause, visibility and SDK-rate cleanup |
| Manual selection counted only video elements | A playable timing surface could report no eligible video | Validate and select recognized playable timing surfaces without inventing video or reward events |
| Optional timer-wrapper assignment could throw during initialization | One read-only timer property prevented independent engine features from loading | Guard optional hooks independently and report installation failures |
| MAX compared a public mediated ad directly with an internal AppLovin creative | Real reward callbacks could never match the mocked same-object relationship | Validate the concrete AppLovin adapter ownership chain; unrelated mediated adapters abstain |
| Native context polling required a recognized controller | Initially hidden unknown MRAID surfaces could remain inactive after becoming visible | Refresh attached tracked webviews while retaining visibility checks |
| Window-local hit tests could overlook a covering content window | A covered MRAID surface could self-recognize again | Require visible surface membership across app windows |
| Failed Actions jobs uploaded a same-SHA artifact that blocked retry uploads | A retry could fail on artifact-name conflict | Explicit artifact replacement |
| Simulator output survived startup failure on reused local builds | An old passing report could accompany a new build | Clear the requested report before starting; record source revision and test mode |
| Initial simulator enumeration could time out before any behavior test | Infrastructure failure prevented the injected checks | One bounded startup retry; assertion failures remain failures |

Code, tests and build tools now live under `project/`. GitHub's required workflow directory and top-level documentation/license notices remain at the repository root.

The previous 34-check native result was against `00a45bf`, not these follow-up changes. Passing browser or mocked SDK tests does not establish real-game rewards. [Ad formats and explicit limits](AD_TYPES.md).

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
