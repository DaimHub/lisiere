# Changelog

## Unreleased

- Make private windows independent, always dark and fresh, without profile cookies, cache or saved browsing state.
- Animate the transparent mascot and track the cursor with its pupils; respect Reduce Motion.
- Fade between profiles in the same window while preserving live tabs.
- Save themes, website appearance, accent colors and mascot choices per profile. Choose the accent when creating or editing a profile.
- Keep every Settings tab label and icon visible when switching profiles.

- Add persisted System, Light, and Dark appearance choices for regular profile windows; private windows always use Dark.
- Let websites follow Lisière by default, with a switch to choose a separate Light or Dark website theme. Preferences persist without forcing site colors or reloading pages.
- Improve address focus, selected suggestions, bookmark hints, and private-window badge contrast.

## 0.1.0 — 2026-10-16

Initial independent fork of Athas Browser at `f7a7e4c6232aa9c8ca2e9c926fa3d79efc9953b5`.

- Name the app Lisière and isolate its bundle identifier, storage fallbacks, and keychain marker.
- Point updates at DaimHub/lisiere; keep them disabled until a fork-specific key is configured.
- Retain AGPL-3.0-or-later, Athas credits, upstream history, and third-party notices.
- Bundle the license and credits in the app.
- Add Make commands, an explicit test scheme, macOS CI, and guidance for future development. The signed test host permits process termination; the Release app retains its sandbox and hardened runtime.
- Adapt the release workflow and include corresponding source and notices with each release.
- Use AGPL contributions without a separate CLA; archive the upstream agreement for provenance.
- Await JavaScript results before XCTest assertions in the inherited password-origin test, preserving its checks.
- Fix local startup with Sparkle by scoping a library-validation exception to ad hoc builds. Keep distribution entitlements unchanged and exercise real startup in CI.
