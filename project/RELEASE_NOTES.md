# AdVanish 0.8.5

Choose your download:

- **rootless.deb** - standard rootless jailbreaks.
- **jailed.zip** - arm64 IPA injection; inject and re-sign before installing.
- **rootful.deb** - traditional rootful jailbreaks.
- **roothide.deb** - RootHide bootstraps only.

Jailbreak DEBs include **arm64 and arm64e**. Choose by jailbreak, not chip.

Changes:

- Recognize a much broader set of ad SDK full-screen controllers (Google, AppLovin/MAX, Unity, ironSource, Vungle, Chartboost, AdColony, Mintegral, InMobi, Amazon, Smaato, MoPub) using the original prefix/suffix heuristic, so renamed or newer SDK controllers are not missed.
- Keep all prior fixes: Hide App Store prompts, manual-only button, categorized settings, CFPreferences, rootless prefs path.

Real game rewards and physical-device compatibility remain unverified.

# AdVanish 0.8.4

Choose your download:

- **rootless.deb** — standard rootless jailbreaks.
- **jailed.zip** — arm64 IPA injection; inject and re-sign before installing.
- **rootful.deb** — traditional rootful jailbreaks.
- **roothide.deb** — RootHide bootstraps only.

Jailbreak DEBs include **arm64 and arm64e** for supported older and newer iPhones. Choose by jailbreak, not chip. A compatible jailbreak or IPA signing setup is still required.

Changes:

- Add per-app **Hide App Store prompts** for supported store sheets, overlays and links during ads.
- Hide the manual button in automatic mode and keep at most one control per active app scene.
- Exclude Apple system processes and app extensions from the runtime.
- Preserve automatic mode when changing button visibility. Reopen the app after changing its settings.
- Shared checks run first, then rootless → jailed → rootful → RootHide.
- Settings changes use CFPreferences and the current rootless preferences path.
- Hiding the fast-forward button keeps automatic mode active.
- 80x playback target with lower-rate fallback; native countdowns accelerate during a visible ad.
- Failed simulator recovery stops the checks.
- Idle macOS queues retry once on Intel.

Real game rewards and physical-device compatibility remain unverified.
