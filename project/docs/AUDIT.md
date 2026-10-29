# Fixes

| Issue | Change |
| --- | --- |
| Manual button did not disable automatic actions | Separate automatic mode; manual mode requires a press |
| Nested MRAID frames lost ad context | Propagate visible parent authorization and revoke it when covered |
| Decorative videos blocked playable requests | Recognized playables can request timing without changing paused, looped or ended videos |
| Mixed native/web ads looked ambiguous | Allow one validated native item and web surface belonging to the same SDK creative |
| Some players reject 16x | Try 16x first, then supported 8x/4x/2x rates; preserve cleanup and SDK base rates |
| CSS animations stayed at normal speed | Bounded animation-rate leases with pause and visibility cleanup |
| MAX callback and creative were different objects | Validate the actual AppLovin adapter ownership chain |
| AppLovin X was not a UIControl | Record its SDK tap registration; activate only after matching genuine completion |
| Stale media retained manual speed | Revoke authorization on source, item, creative or ownership changes |
| Failed builds retained stale reports/artifacts | Clear reports before startup; allow artifact replacement on reruns |
| RootHide uses a randomized root | Separate toolchain and package; resolve preference paths through jbroot |

[Tests](VALIDATION.md) · [SDK evidence](ANALYSIS.md) · [Ad types and limits](AD_TYPES.md).
