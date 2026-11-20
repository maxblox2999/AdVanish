# AdVanish 0.8.14

- Retry an ignored eligible Close control up to five times, with at least 750 ms between attempts.
- Recheck the ad, reward requirements and control before each attempt.
- Fix cancellation callbacks when an SDK reuses its App Store product sheet.
- Recognize Unity and Mintegral controller subclasses for completion handling.
- Keep 80x acceleration and manual mode.

Downloads: rootless.deb for rootless jailbreaks, rootful.deb for rootful, roothide.deb for RootHide, or jailed.zip for IPA injection and re-signing. DEBs contain arm64 and arm64e; the jailed framework is arm64.

Prerelease. Simulator and package checks do not establish coverage of every real ad. Automatic Open Store transitions and whole-app acceleration are not implemented. iOS 15–18 targets; iOS 26 is experimental with a low chance of working.
