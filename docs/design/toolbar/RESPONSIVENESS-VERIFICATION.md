# Toolbar responsiveness and Profile interaction — 2026-10-16

This follow-up addresses the user's report that the previous drag interaction felt worse after enabling animated gaps. Product Design uses the existing native editor and toolbar as its target.

## Changes

- Replaced animated gaps with AppKit's regular insertion indicator. Hovering a standalone row resolves to its nearest insertion edge instead of creating a group. The Group With menu remains the explicit way to create or merge groups; dropping between children can join an existing group.
- Applied changes to the native outline immediately on drop or arrow activation. Sibling reorders use `moveItem` instead of `reloadData`; unchanged SwiftUI updates do nothing. Selection, scrolling and collapsed groups survive moves. No model writes happen during drag hover.
- Excluded Profile and Address from grouping at the model, menu and drop-target levels. Saved groups containing either control split around them while preserving the action order.
- Moved the Profile badge's entire 132 × 34 pt footprint into the menu label (34 × 34 pt when compact). The badge has full-surface hover/pressed styling and one accessible menu element. Navigation/profile actions remain owned by BrowserWindow and ProfileStore.

The native insertion and move behavior follows Apple's [NSOutlineView contract](https://developer.apple.com/documentation/appkit/nsoutlineview) and the installed AppKit SDK headers.

## Validation

`make test DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/Lisiere-Toolbar"` passed 196 tests with zero failures in 44.338 seconds. The 16 toolbar tests include exclusion/migration, insertion edges, native pasteboard images, per-profile persistence, and 60 native sibling moves without a full outline reload. The native move test also checks selection, collapsed groups, child reordering and structural separation. It is a regression check, not a measurement of physical gesture latency.

Release builds succeeded and the Release/isolated QA bundles passed `codesign --verify --deep --strict`. Native QA verified left and right padding clicks open the Profile menu, arrow moves update the preview and rows immediately, and Profile/Address grouping controls are visibly disabled. The final accessibility tree exposes a single Profile menu control.

Logs: `/tmp/lisiere-toolbar-responsive-tests.log`, `/tmp/lisiere-toolbar-responsive-build.log`. The unchanged ProfileAccent actor-isolation warning and local CoreSimulator version warning remain outside this macOS change.

The [final QA editor capture](responsive-settings.jpg) shows separate Profile/Address rows, their disabled grouping controls and the preserved button groups. The final Profile menu also exposes one accessible control instead of separate icon/text/chevron elements.

## Installation

The user's normal app was closed before replacement. The previous app and 10,596 readable data files were backed up at `~/Library/Application Support/Lisiere Release Backups/toolbar-responsive-2026-10-16-214757`. All data-file hashes matched before relaunch, and the installed app matches the Release bundle. Installed strict signature verification passed.

Native relaunch restored the four tabs and selected New Tab. The customized action order remained Home, Profile, Back, Forward, Reload, New Tab, Address and All Actions. Profile opens its native menu and remains one accessible menu control. The existing Profile/Address controls now remain outside button groups.

Physical drag feel and hover appearance still need direct user confirmation because the macOS automation tool does not faithfully deliver continuous pointer gestures. A test was requested with the final isolated QA copy open. The automated checks and native click evidence do not establish subjective smoothness or a physical hover transition.
