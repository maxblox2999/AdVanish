# AdVanish 0.8.10

Choose your download:

- rootless.deb - standard rootless jailbreaks.
- jailed.zip - arm64 IPA injection; inject and re-sign.
- rootful.deb - traditional rootful jailbreaks.
- roothide.deb - RootHide bootstraps only.

DEBs include arm64 and arm64e. Choose by jailbreak, not chip.

Changes:

- Add per-app Banners → Block ad banners, off by default.
- Block Google AdMob and Ad Manager banner load requests and remove their SDK views.
- Preserve ordinary game UI, 80x speed, manual mode and completed-ad closing.
- Jailed configurations accept BlockBanners.

Reopen the app after changing banner settings. Custom game-reserved space can remain. This does not block native feeds, full-screen ads or unknown banner SDKs.

Simulator tests use mock SDK classes. Real games, rewards and physical devices remain unverified.
