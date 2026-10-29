# Completion support

| Path | Implemented behavior | Limit |
| --- | --- | --- |
| Owned AVPlayer / HTML video | 16x rate, natural playback completion, pause and visibility cleanup | The player may reject the rate; no seeking or fake `ended` event |
| Detected MRAID playables | Existing timer/clock acceleration plus animation timestamps; bounded input on explicit gameplay controls | Unknown canvas logic and trusted-touch checks cannot be solved generically |
| Google rewarded / rewarded interstitial | Observe the original reward handler; eligible SDK Close action after the matching reward | Requires a recognized controller and accessible SDK-owned control |
| Google interstitial / app-open with native video | Observe real player-end notifications for the captured items, then request eligible SDK Close | HTML-only, static and unknown completion paths abstain |
| MAX rewarded through the AppLovin adapter | Observe genuine display/reward events after validating the callback ad, adapter wrapper and loaded AppLovin creative against the controller's creative | Other mediation adapters abstain unless an exact ownership relation is available |
| AppLovin gesture-driven X view | Use the SDK's recorded tap registration on its own current Close view after a matching reward | Missing, replaced, disabled or unrelated gesture registrations abstain |
| Unity / LevelPlay / other reward callbacks | Original SDK and app behavior preserved | No automatic reward-based dismissal adapter unless exact session ownership is established |
| Ad redirects | Block supported MRAID/window and external URL opens inside the active ad context | Direct navigation and SDK-specific store presentations may remain unsupported |
| Manual button | Same 16x playback target plus selected recognized playable timing; validated selection across native players and web frames | Ambiguous, hidden, stale or inaccessible surfaces abstain |

Detection uses ad surfaces and SDK ownership, not a list of game bundle identifiers. The manual fallback can act on ordinary video when pressed outside an ad.

**Automatic ads** enables automatic acceleration, input and supported Close actions. With it off, the button is required for acceleration and automatic input/Close stay disabled. **Show fast-forward button** independently controls visibility in automatic mode. Existing explicit manual preferences default to manual mode until overridden.

Playable input recognizes `Tap to play`, `Start game`, `Continue playing` and `Swipe left/right/up/down` on visible semantic controls. It checks at most 128 controls per scan and performs at most 12 actions per ad context. Unknown canvas coordinates, install controls and links are not guessed. MRAID discovery requires a ready, viewable interstitial; hidden or covered frames lose authorization.

The tweak never invokes a reward callback, game-end bridge or server verification request to manufacture completion. A genuine client reward event is not proof that the game's server credited the account.

All real SDK behavior, game rewards and signed-device injection still require physical-device testing. Fixtures cover their own declared contracts; they are not substitutes for those results.
