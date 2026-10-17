# Pins, group drops and window controls — 2026-10-17

Drops now commit on release, with an insertion marker. Dropping beside a tab can change its group while preserving its pinned state. Group headers accept empty or collapsed groups; dropping on New Tab removes group membership. Joined split cards move together. Typed, process-local payloads replace the stale view-local drag ID, and ordinary text or another window's tabs are rejected. Hovering alone does not modify the session.

Window controls are laid out after AppKit's titlebar pass. The inner titlebar and outer container use the same row height, and frame changes on either titlebar view or the standard controls schedule a coalesced repair. Full-screen windows keep AppKit's layout.

## Verified

- `make test`: 262 tests pass. Coverage includes pin ordering in both directions, cross-group insertion, empty/collapsed groups, removal from a group, split pairs, invalid IDs, typed payload loading, suspended pages and unchanged selection.
- Native AppKit regression: resetting the inner titlebar and standard controls reproduces a control center 35 pt from the top before the fix; the corrected vertical row centers it at 23 pt. Tests also reset only the buttons, alternate 40/46 pt rows, and resize the window.
- Release build, strict code signing and startup smoke pass in the dedicated `LisierePinnedGroups` build directory. The isolated `Lisiere Pins QA.app` retains sandbox and hardened runtime.
- In that Release, horizontal/vertical switching and switching between two profiles with different layouts preserve the browser window, pinned tabs, group and selection. Pin menus omit Close Tab. Clicks and native context menus remain usable.

## Manual acceptance remaining

The computer-control drag starts the native drag but never reaches a drop callback, both in Lisière and in an independent minimal SwiftUI drag/drop application (one start, zero drops). This prevents an automated end-to-end claim for the pointer gesture. Model and payload tests pass; a physical mouse/trackpad test must still check pin reordering, dropping into a collapsed group, dropping beside a tab in another group, and cancelling a drag.

The automation's screen-sharing badge covers the traffic lights in screenshots; exact control positioning is checked by native AppKit geometry assertions instead.
