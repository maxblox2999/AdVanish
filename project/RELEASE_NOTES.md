# AdVanish 0.8.3

Choose your download:

- **rootless.deb** — standard rootless jailbreaks.
- **jailed.zip** — arm64 IPA injection; inject and re-sign before installing.
- **rootful.deb** — traditional rootful jailbreaks.
- **roothide.deb** — RootHide bootstraps only.

Jailbreak DEBs include **arm64 and arm64e** for supported older and newer iPhones. Choose by jailbreak, not chip. A compatible jailbreak or IPA signing setup is still required.

Changes:

- Shared checks run first, then rootless → jailed → rootful → RootHide.
- Settings changes use CFPreferences and the current rootless preferences path.
- Hiding the fast-forward button keeps automatic mode active.
- 80x playback target with lower-rate fallback; native countdowns accelerate during a visible ad.
- Failed simulator recovery stops the checks.
- Idle macOS queues retry once on Intel.

Real game rewards and physical-device compatibility remain unverified.
