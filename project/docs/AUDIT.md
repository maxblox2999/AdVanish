# Fixes

| Issue | Change |
| --- | --- |
| Only five ad controllers were recognized | Recognize common SDK full-screen controllers and ad-named controllers |
| Turning off the fast-forward button disabled automatic mode | Derive the automatic default from the new manual value |
| Settings could not be saved on rootless | Prefer the real preferences path, then the /var/jb copy |
| Settings changes did not reach other apps | Write through CFPreferences as well as the plist |
| Manual button did not disable automatic actions | Separate automatic mode; manual mode requires a press |
| Nested MRAID frames lost ad context | Propagate visible parent authorization and revoke it when covered |
| Decorative videos blocked playable requests | Recognized playables can request timing without changing paused, looped or ended videos |
| Mixed native/web ads looked ambiguous | Allow one validated native item and web surface from the same SDK creative |
| Some players reject 80x | Try 80x, then 40x/20x/16x/8x/4x/2x; preserve cleanup and SDK base rates |
| CSS animations stayed at normal speed | Bounded animation-rate leases with pause and visibility cleanup |
| MAX callback and creative were different objects | Validate the actual AppLovin adapter ownership chain |
| AppLovin X was not a UIControl | Record its SDK tap registration; activate only after a matching genuine completion |
| Stale media retained manual speed | Revoke authorization on source, item, creative or ownership changes |
| Native countdowns ran at real speed | Compress 0.5-30s NSTimer intervals while an ad surface is active |
| Nested timer constructors compressed twice | Track construction depth per thread and compress once |
| Disabled apps still received hooks | Gate injection, playback and timers on the master and per-app switches |
| Failed builds retained stale reports | Clear reports before startup; allow artifact replacement on reruns |
| RootHide uses a randomized root | Separate toolchain and package; resolve preference paths through jbroot |

[Tests](VALIDATION.md) - [Ad types and limits](AD_TYPES.md).
