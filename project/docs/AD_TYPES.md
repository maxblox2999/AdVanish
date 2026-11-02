# Ad support

Automatic mode accelerates video and web timing throughout enabled apps, including non-ad content. Detection controls interaction and closing. Recognition alone does not mean an ad can finish automatically.

| Ad type | Acceleration | Automatic closing |
| --- | --- | --- |
| AVPlayer video | 80x, then 40x/20x/16x/8x/4x/2x if rejected; no seeking | Supported Google video completion or a matching SDK reward event |
| HTML video and nested frames | Playback speed; manual mode selects an eligible surface | Requires native SDK eligibility |
| MRAID, HTML5 and time-based playables | JS timers, clocks, animation frames and running CSS/Web Animations | Requires native SDK eligibility |
| Playables with exposed controls | Limited tap/swipe assistance in automatic mode | Requires native SDK eligibility |
| Playables with decorative video | Manual timing leaves paused, looped and ended video alone | Requires native SDK eligibility |
| One SDK-owned native/web pair | One manual request can accelerate both parts | Requires native SDK eligibility |
| Canvas/WebGL | Time-based logic may accelerate; fixed-step logic may not | No generic gameplay solver |
| Native countdowns | 0.5-30s NSTimer intervals during a detected ad | SDK and server requirements still apply |
| Video followed by an end card | Each phase keeps its own completion requirements | Video ending alone cannot close a mixed or rewarded session |
| Google banner views | Optional Block ad banners, off by default | Blocks SDK loads and removes views; game-reserved space can remain |
| Other banners and native feeds | No dedicated removal adapter | Unsupported |
| Workers, remote gates and trusted-touch creatives | Worker clocks are not hooked | May require real interaction |

## Completion paths

- Google rewarded: the captured ad must receive its original SDK reward callback.
- Google video interstitial/app-open: captured video items must finish, without a mixed web phase.
- AppLovin MAX: reward and creative must belong to the validated AppLovin adapter.
- AppLovin X view: the visible Close view must retain its enabled SDK tap registration.
- Other mediation adapters: no reward-based closing without a supported ownership path.

Unity containers and recognized MRAID, VPAID, HSADX, VSDK and Canvas/WebGL surfaces can use the existing acceleration. Other networks receive app-wide playback and web timing without a dedicated reward adapter.

Manual mode waits for a button press and never closes automatically. It does not solve arbitrary games or grant rewards. Replacing a playable's selected node requires another press.

Opaque frames, ambiguous surfaces, remote waits and inaccessible Close controls remain gaps. Real-game closing and rewards need physical-device tests. See [test scope](VALIDATION.md).
