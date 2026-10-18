# Pins, group drops and window controls — 2026-10-18

Tab moves use a window-local SwiftUI drag gesture. The previous NSItemProvider path did not reliably reach a drop, so passing model tests was insufficient. The gesture now tracks visible tab and folder bounds directly, displays an insertion marker or folder outline, and commits only on release. It keeps the existing BrowserModel operations, tab objects, selection, pin state and split pairs.

Drop on a folder header to join it, including an empty or collapsed folder. Drop before/after a tab to join its group at that position. Drop in the empty sidebar or its temporary “Move out of group” footer to remove membership. The horizontal strip has the same destination after the add button. Escape, switching windows, or releasing outside the strip cancels the move. Clipped rows cannot intercept another scroll area's drops; edge scrolling follows the actual layout axis. Hover previews are suppressed during dragging.

Window controls retain the previous AppKit repair: inner titlebar and outer container share the row height, frame changes schedule a coalesced repair, and full-screen windows keep AppKit's layout.

## Verified

- `make test`: 267 tests pass. Six controller tests cover release-only commits, group removal without unpinning, cancellation, clipped and invalid targets, insertion position and edge-scroll geometry. Existing model tests cover pins in both directions, cross-group insertion, empty/collapsed groups, split pairs, suspended pages and selection preservation.
- Pointer gestures in the isolated signed Release actually changed the UI: horizontal pin reordering; horizontal folder entry and exit; sidebar pin reordering across rows; regular tabs entering, leaving and moving between folders; insertion before another folder's tab; dropping into a collapsed folder; moving a pin into and out of a folder while keeping it pinned. Folder counts and tab order were checked after release.
- Releasing over web content leaves the original folder unchanged. Ordinary tab selection, the Close button and native context menus remain usable.
- The QA bundle retains sandbox and hardened runtime. Full Release signing, startup and installation checks are performed against exact bundle paths.
- Native AppKit regressions continue to check traffic-light positioning after titlebar/button resets, alternating row heights and resizing. The automation's screen-sharing badge covers the traffic lights in screenshots, so screenshot evidence does not establish their exact position.

## Coverage boundary

The controller tests cover Escape and continuous edge-scroll decisions. A held physical mouse/trackpad gesture with Escape or prolonged edge scrolling has not been exercised. Pointer-based membership and reorder behavior above was exercised end to end, rather than inferred from the model tests.
