# Appearance and animation

Settings > Appearance edits the selected profile: System, Light or Dark theme, separate website appearance, tabs, bookmarks and mascot. Settings > Profiles > New Profile or Edit chooses one of six accent colors for that profile. Choices persist in the existing profile preferences; the initial Personal profile keeps its original preferences and data. Copying a profile copies these explicit preferences without copying website state.

Each profile owns an `AppearanceStore`. The scene root applies `preferredColorScheme` so SwiftUI, native window controls and panels agree. System removes the preference; the application itself follows macOS. Web views retain their owning profile's appearance through switching, pop-ups, duplication and restoration. The accent colors controls, the address focus outline, loading indicator and new-tab background. Websites choose their own styles; no forced color inversion or page reload is used.

Private windows are independent of profiles and always dark, with a fresh nonpersistent WebKit store per window. They never load saved cookies, cache, passwords, bookmarks, history, tracker exceptions, favicon files or Find text. Tabs within one private window share its temporary state; another private window starts empty. Saved downloads remain on disk.

The original transparent `Mascot-*` artwork is animated using its existing body, eye and pupil layers. The mascot floats gently and blinks; pupils track the cursor only within the active native window. Tracking is removed when the view disappears. Reduce Motion disables floating, blinking, pupil tracking and profile fades. Switching profiles uses a 300 ms opacity transition and retains the exact live tabs in the same physical window.

## Cloud integration

The unpublished cloud changes from chat `01a14559-b556-7393-a987-9b3702f78050` were exported without modification, with all 24 file hashes verified. Archive SHA-256: `5ef2de9d688aceff0785edcbc3c6e5a9edda17d687ea5fbb48e7ca1defb12849`.

The cloud implementation started from `c94828f` and introduced a different profile registry and a replacement mascot. Integration retains the existing local registry, profile identifiers, storage locations, Keychain separation, profile window controller and transparent artwork from `7a28738`. Appearance and private-session behavior are ported onto these owners; source export stays available in ignored `.build/cloud-export` for comparison.

## Local release validation — 2026-10-16

- The 178-test XCTest suite passed after the scene-theme and Settings-tab fixes. Real WebKit tests cover cookie, localStorage, IndexedDB, cache and service-worker separation, including fresh independent private windows. Cookie-test teardown now waits for WebKit to release its test-only network store.
- The universal arm64/x86_64 Release passed strict deep signature verification with the sandbox and hardened runtime retained. An isolated Release passed the startup smoke check.
- Native Release inspection confirmed a dark private window, dark profile and Settings windows, all seven labeled Settings tabs, distinct light/dark profiles, per-profile accent changes, and moving mascot pupils and body. Profile switching retained the same physical window. Screenshots do not establish frame-by-frame fade timing.
- The final accent-control relocation was rebuilt and inspected in the installed Release: Profiles > Edit contains the color selector and Appearance no longer does. Tab metadata uses stable `Tab` declarations outside profile-dependent content identities.
- `/Applications/Lisiere.app` was updated. Its executable, assets and Info.plist matched the final build. The previous app and 7,629 app-data files were backed up and hash-verified before replacement; installation left those data files unchanged before launch. Personal and Pro retained their identities, preferences and restored sessions. The active Personal profile was then explicitly set to Dark at the user's request.
- Physical trackpad gestures, full keyboard/VoiceOver coverage, new account authentication, passkey entitlements and notarized distribution were not exercised.

## Historical validation before per-profile themes

- 118 XCTest tests passed, including nine appearance tests and the complete upstream suite.
- The canonical Release build passed strict deep signature verification. The isolated validation Release also passed startup smoke with the standard local Release sandbox and hardened runtime.
- The built native Release was inspected on macOS 27.0 (26A428): light/dark settings, both tab layouts, address focus and selected suggestions, private windows, tab menus, native prompt sheets, and history. Separate app/site themes worked in both directions; switch-off inheritance, switch-on recall, and relaunch persistence were observed with an adaptive local page. Its media query changed without reloading; author-fixed white content and a light-only page stayed white.
- macOS 26, a live system-wide light/dark change while System is selected, full VoiceOver/Increase Contrast coverage, and distribution signing/notarization were not exercised. Find-field keyboard validation was inconclusive. The pre-existing private welcome text truncation at minimum height remains outside this appearance change.

The validation used a separate app identifier and profile. No installed browser or user profile was replaced.
