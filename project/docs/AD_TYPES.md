# Ad support

Automatic mode targets 80x video and web timing inside enabled apps, including non-ad content. Detection controls interaction and closing.

| Content | Acceleration |
| --- | --- |
| AVPlayer video | 80x, with 40x/20x/16x/8x/4x/2x fallback; no seeking |
| HTML video and nested frames | Playback speed and frame timing |
| MRAID, HTML5 and time-based playables | JS timers, clocks, animation frames and CSS/Web Animations |
| Native countdowns | NSTimer waits from 0.5 to 30 seconds during a detected ad |
| Canvas/WebGL | Time-based logic may speed up; fixed-step logic may not |

## Closing

- Google rewarded: wait for the original SDK reward callback.
- Google video interstitial/app-open: captured video items must finish without a mixed web phase.
- AppLovin MAX: match the reward to its AppLovin adapter and creative. Native X views need their original SDK tap registration.
- Unity: use the SDK's visible, enabled web Close control.
- Mintegral: playable skip, final Close and native X handling are under device testing.

Other mediation adapters need their own completion path. Detection alone does not mean an ad can close automatically.

Manual mode acts only after a button press and never closes automatically. It can accelerate one SDK-owned native/web pair and supported countdowns without changing paused, looped or ended decorative video. Replacing the selected playable node requires another press.

Optional banner blocking covers Google AdMob and Ad Manager views. Game-reserved space may remain; other banner SDKs and native feeds are unsupported.

MRAID, VPAID, HSADX, VSDK and recognized Unity surfaces retain acceleration. Worker clocks, remote waits, trusted-touch requirements and inaccessible frames remain gaps. Playable assistance is limited; there is no general gameplay solver. Rewards stay with the SDK and server.

[Test scope](VALIDATION.md)
