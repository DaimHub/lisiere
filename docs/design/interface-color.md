# Interface color

Appearance offers Original, Sage, Ocean, Sand, Clay, Lavender and Custom for each profile. Original preserves the existing window material and is the default, including for unknown saved choices. A single restrained wash covers the sidebar and horizontal toolbar in both tab layouts. BrowserChrome dimensions, native control states, profile accent colors, website themes and transparent animated mascots keep their existing owners. Private windows retain their independent dark violet appearance.

Custom colors retain hue with bounded saturation and brightness for light and dark appearances. The native color picker has no opacity control. A six-digit RGB field accepts an optional #; Return or leaving the field applies valid input, while invalid input retains the previous color and shows feedback. Palette and custom RGB persist independently, so Original does not discard a custom choice.

AppearanceStore uses the profile's optional defaults. The keys participate in profile copying; private preferences remain ephemeral. BrowserWindow renders the tint inside its profile workspace, retaining the stable window material and existing crossfade. Changing color does not reload web views. The latest pending mascot-visibility option also uses ProfilePreferences and leaves MascotView animation and Dock selection intact.

## Integration and validation — 2026-10-16

Integrated on `214466a`, the source of the installed profile-crossfade Release, including toolbar customization, draggable groups, the expanded profile menu target, profiles and animated mascots. The older working checkout remains untouched. Its preview had fixed horizontal-layout and new-tab buttons in the sidebar header; the current TabStrip and user toolbar configurations are retained.

- `make test`: 202 tests, zero failures. New coverage includes fallback/persistence, website-theme independence, text contrast, independent profile colors, profile copying, mascot visibility and ephemeral preferences. Existing toolbar/profile/crossfade tests also pass.
- `make build`: universal locally signed Release. Build and installed app pass `codesign --verify --deep --strict`; executable hashes match. Sandbox and hardened runtime remain enabled.
- Isolated native Release (`io.github.daimhub.lisiere.interfacecurrentqa`): Sage in both layouts, custom orange in dark mode, mascot hiding, and private violet inspected. Custom hex submission updates the native color well. Native picker interaction was only partially exercised in the earlier preview; its connected editing path is not claimed as an end-to-end check.
- Installed native Release: Perso and Pro reopen with their distinct toolbar configurations and bookmarks. Appearance exposes the new palette for the selected profile. Sage was applied and visually checked, then Original restored. The installed app remains open on Perso. Both QA apps are closed.
- Before replacement, the old app and data were backed up to `~/Library/Application Support/Lisiere Release Backups/interface-color-2026-10-16-222605`. All 10,638 regular data-file hashes matched the backup and remained identical after app replacement, before relaunch. macOS-owned container metadata was excluded. Normal runtime session writes occur after launch; the final profile registry and histories remain intact.

Logs: `/tmp/lisiere-interface-current-test.log` and `/tmp/lisiere-interface-current-build.log`. DerivedData: `Lisiere-InterfaceColor-Current`. This verifies local ad hoc installation; Developer ID distribution, account sign-in and physical trackpad gestures were not exercised.
