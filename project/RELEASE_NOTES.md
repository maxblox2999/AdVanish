# AdVanish 0.5.2

- Remove title updates from Settings row construction to prevent reentrant loading.
- Keep the row cache mutable and guard unavailable or incorrectly typed app-registry getters.
- Add a dedicated simulator test that opens the root and app Settings pages using Apple's Preferences framework.

Test release. The exact device crash cannot be confirmed without its crash report. Physical PreferenceLoader and jailbreak behavior remain unverified.
