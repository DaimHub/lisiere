# Toolbar verification — 2026-10-16

Implemented on `codex/customizable-toolbar`, based on `8636668d7c41b0e60bac47bf36de7798aca06e27`, which matches the installed profile/accent feature baseline. The original checkout and its unrelated mascot work were left untouched.

## Automated checks

- `make test DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/Lisiere-Toolbar"`: 186 tests passed, zero failures; final run completed at 21:00:13 CEST. Includes six new tests covering malformed preferences, required controls, customization, per-profile persistence/copying, overflow/download presentation, and Home preserving open pages.
- `make build` with the same derived-data directory: Release succeeded.
- `codesign --verify --deep --strict` passed for the built and installed Release. Release retains sandbox and hardened runtime with the project's existing local ad hoc entitlements.
- `git diff --check` passed.
- The inherited `ProfileAccent.swift` actor-isolation warning remains outside this change.

## Native Release checks

An independently signed QA copy with bundle ID `io.github.daimhub.lisiere.toolbarqa` kept exploratory settings and tabs separate from user data. Native screenshots and accessibility state were inspected, without a web prototype.

Confirmed in the native QA Release:

- Default order: Profile, Back/Forward/Reload, Address, New Tab; no layout toggle or duplicate New Tab in either tab layout.
- Light regular windows and dark private windows, with matching control geometry and readable URL field.
- Add Home, Private Window, History and Downloads; move Home using the explicit arrows; immediate preview and toolbar update; persistence across relaunch; Restore Default.
- New Tab adds a tab; address navigation loads a page; Home opens the start page without replacing the existing page; Private opens a private window; Downloads displays its empty state.
- The final editor uses arrows to reorder. Drag-and-drop is not implemented.

Snapshots: [customization editor](settings.png), [private window](private.png). The purple sharing indicator and pointer halo in captures belong to macOS/computer automation.

## Installed app and data

After the user closed Lisière normally, the previous app and data were backed up to:

`~/Library/Application Support/Lisiere Release Backups/toolbar-2026-10-16-210229`

The installer verified 10,566 readable regular files against their backup hashes and confirmed they were unchanged before relaunch. The staged and installed application matched the built Release byte-for-byte. The running app can naturally update its session/cache files after launch.

`/Applications/Lisiere.app` was relaunched and inspected. The expected Profile → navigation → URL → + order is visible, the horizontal-layout toggle is absent, and all three existing tabs were restored. Existing profile names and the current public page were confirmed. The installed screenshot is kept locally at `/tmp/lisiere-toolbar-installed.png`; it is excluded from this repository because it includes personal tab labels.

## Evidence limits

Narrow-width overflow is covered by the presentation tests; physical narrow-window resizing was not established through the automation tool. Full VoiceOver operation, every optional action in every combination, account authentication, passkeys, Developer ID signing/notarization and Sparkle distribution were not revalidated. Customization interactions were verified in the isolated native Release; the installed app check covered startup, toolbar appearance and session restoration.

Local logs: `/tmp/lisiere-toolbar-final-tests.log`, `/tmp/lisiere-toolbar-release.log`. XCTest result bundle: `~/Library/Developer/Xcode/DerivedData/Lisiere-Toolbar/Logs/Test/Test-Lisiere-2026.10.16_20-59-18-+0200.xcresult`.
