# Pins, group drops and window controls — 2026-10-18

Tab moves use a window-local SwiftUI drag gesture. The previous NSItemProvider path did not reliably reach a drop, so passing model tests was insufficient. The gesture now tracks visible tab and folder bounds directly, displays an insertion marker or folder outline, and commits only on release. It keeps the existing BrowserModel operations, tab objects, selection, pin state and split pairs.

Drop on a folder header to join it, including an empty or collapsed folder. Drop before/after a tab to join its group at that position. Drop in the empty sidebar or its temporary “Move out of group” footer to remove membership. The horizontal strip has the same destination after the add button. Escape, switching windows, or releasing outside the strip cancels the move. Clipped rows cannot intercept another scroll area's drops; edge scrolling follows the actual layout axis. Hover previews are suppressed during dragging.

Window controls retain the previous AppKit repair: inner titlebar and outer container share the row height, frame changes schedule a coalesced repair, and full-screen windows keep AppKit's layout.

## Opening folders during a tab drag

Holding a site over a collapsed folder header for 500 ms opens it in either layout, for both pinned
and ordinary sites. The folder stays open while the pointer is within its visible section, including
child cards, internal gaps and child targets that cannot accept this site's pin state. This allows a
drop at a precise child position without closing the folder when leaving its header. Only expansion
changes during the hover: membership, order, selection and page objects remain intact until release.
Moving inside the same header or refreshing its geometry does not restart the delay. Leaving the header,
clipping it out of its viewport, cancelling, releasing or replacing the drag controller cancels pending
expansion. The callback rechecks the live source and target, so closing a site or removing a folder cannot
trigger stale work. Whole-folder reordering never opens the folder underneath. One cancellable task runs
per hovered folder; there is no polling loop.

Folders opened by this hover close 300 ms after leaving their visible section, including when scrolled
out from under the pointer. Returning anywhere inside cancels that close; a later exit receives a fresh
300 ms grace period. Pointer jitter and geometry refreshes outside do not postpone its deadline.
Cancellation or an invalid release restores the folder immediately and cancels pending work. A successful
header or child drop keeps the receiving folder open. Folders that were already open, or opened independently before the hover deadline, are never auto-collapsed. The drag
controller tracks only the folder it actually expanded and restores it before forgetting the original
window, including when the source site or target folder disappears. Expansion and re-collapse preserve
membership, pin state, order and selection.

## Folder interaction states

Pinned and ordinary folder headers share the same native button style in both layouts. At rest, a
light tint and quiet border identify the folder; a folder containing a visible page keeps a stronger
resting tint. Hover strengthens the fill and border. Pressing darkens the surface and slightly insets
the label, while the outer header and drop bounds keep their existing dimensions. The disclosure
chevron follows the 240 ms folder transition; hover and release use 140 ms transitions and pressing uses 80 ms.

Each visible section owns its hover state, so hovering a pinned header does not highlight the same
group's ordinary header. Dragging suppresses mouse hover/press decoration and uses the existing drop
outline with a tinted target surface. Keyboard focus receives a distinct ring. Dark appearance adjusts
the fill, increased contrast strengthens borders, and Reduce Motion disables transitions and label
movement while retaining color feedback. Group state, persistence and drag timing are unchanged.

## Opening and closing animation

A shared 240 ms smooth transition animates folder disclosure in both layouts, including header clicks,
context-menu commands, accepted drops and spring-loaded hover changes. Children use a short directional
fade (6 pt vertically, 8 pt horizontally), while adjacent sections and the pinned viewport resize in the
same transaction. The existing tab/page identities and model collapse state remain authoritative; there
is no second delayed copy of the state. Rapid reversals retarget SwiftUI's ongoing transition.

The collapse-state animation excludes the pointer-following drag overlay, so the drag preview remains
responsive. A card fading out cannot accept a stale child drop or accidentally route it to the ungrouped
background before its geometry disappears. The next rendered empty area becomes droppable normally.
Reduce Motion removes the disclosure animation and directional fade. The existing 500 ms hover-open
and 300 ms exit grace periods remain unchanged.

## Folder ordering

Drag a folder header to move the whole folder before or after another section. The insertion marker
uses the layout axis: above/below in the sidebar, left/right in the horizontal strip. Expanded folders
include their child cards in the target bounds. Tab membership drops and folder order drops use separate
targets, so dragging a folder over a child never reparents its sites. The same global order applies to
both pinned and regular sections. Empty folders remain movable; collapse, colors, names, page objects,
selection, pin state and split pairs are preserved. Clicks still toggle collapse and the native menu
retains its keyboard-accessible Move Group Earlier/Later commands.

Dropping a folder in the empty sidebar, its temporary “Move group to end” footer, or the horizontal
space after the add button moves it after the last folder. The move commits on release and is a no-op
when the folder is already last. Visible folder sections and loose tabs take precedence over the
background, so a self-drop or a drop on an ungrouped site cannot accidentally send a folder to the end.

## Verified

- `make test`: 285 tests pass. Controller tests cover release-only commits, group removal without unpinning, cancellation, clipped and invalid targets, insertion position and edge-scroll geometry. Empty-space regressions cover both layouts, moving a folder to the end, already-last drops, preserved folder metadata and pin membership, and occupied regions blocking background drops. Three asynchronous hover tests exercise the real 500 ms task, stable deadlines, retargeting, cancellation, stale source/target removal, folder-drag exclusion, and precise child insertion after expansion with page identity and pin state preserved. Existing model tests cover pins in both directions, cross-group insertion, empty/collapsed groups, split pairs, suspended pages and selection preservation.
- Four further asynchronous regressions cover re-collapse in both layouts, child cards and gaps, invalid pin insertion, re-entry, cancellation/reset, clipped targets, source/target deletion, successful header and child drops, and preservation of independently opened folders.
- Two additional asynchronous regressions cover the 300 ms grace period, header/child/gap re-entry in both layouts, a fresh deadline on the next exit, stable deadlines during outside movement and geometry updates, and pending-task cleanup after a successful drop, cancellation, reset or release before a later gesture.
- An additional regression covers stale child bounds during collapse in both layouts: invalid drops preserve membership, reversing collapse restores the child destination, and the background becomes available after the old frame disappears.
- Pointer gestures in the isolated signed Release actually changed the UI: horizontal pin reordering; horizontal folder entry and exit; sidebar pin reordering across rows; regular tabs entering, leaving and moving between folders; insertion before another folder's tab; dropping into a collapsed folder; moving a pin into and out of a folder while keeping it pinned. Folder counts and tab order were checked after release.
- Folder gestures were verified in both directions and layouts, with empty, expanded and collapsed folders. The sidebar also reordered pinned folders, including one with a matching regular section. Clicking headers still toggles collapse. The shared order survives layout switches and relaunch. Four new regressions cover both axes, section/child target separation, cancellation, clipped targets, mixed pins, split pairs, stable insertion and session encoding.
- Empty-space folder drops were exercised in the signed Release: Recherche moved after Travail in the blank sidebar; dragging Travail's regular header into the horizontal trailing space updated the shared order of its pinned section too. Site counts, colors and active page stayed intact. Repeating the last-folder drop did nothing, and dropping a folder over a loose pin left the order unchanged. The final order survived relaunch.
- With hover expansion installed, Release pointer checks confirmed that a quick pass across a collapsed horizontal folder leaves it closed; a horizontal pin drop and a sidebar ordinary-site drop into collapsed folders still expand them and preserve the active page and pin state.
- With re-collapse installed, dragging pins past already-expanded folders and releasing in empty space preserves those folders in both layouts. A sidebar drop into a collapsed folder still leaves the receiving folder open, with the active page intact.
- With the 300 ms grace period installed, Release checks confirmed horizontal and sidebar pin entry/exit, preservation of already-open folders, and a sidebar drop into a collapsed folder remaining open. Folder counts, pin state and the active page stayed correct. The timed re-entry path remains controller-tested as noted below.
- Folder button styling was checked in the signed Release in light/dark appearance and both layouts. Header clicks still collapse/expand pinned and ordinary sections; sidebar site drops and whole-folder moves in both layouts preserve membership and active content. Resting tints and disclosure states were inspected. The automation did not capture a reliable held-press or hover-only frame, so transient feedback, keyboard focus and system Reduce Motion/contrast remain direct manual checks.
- With disclosure animation enabled, signed Release pointer checks confirmed opening and closing in both layouts, consecutive reversals on pinned headers, and synchronized pinned/ordinary sections of the active folder. Collapsed children disappear without leftover cards; expanding restores them and preserves the active page. A sidebar pin dropped into a collapsed folder opened it and updated the count correctly. Screenshots verify the resulting layout, not frame-by-frame smoothness; transient motion and the system Reduce Motion path remain manual checks.
- Releasing over web content leaves the original folder unchanged. Ordinary tab selection, the Close button and native context menus remain usable.
- The QA bundle retains sandbox and hardened runtime. Full Release signing, startup and installation checks are performed against exact bundle paths.
- Native AppKit regressions continue to check traffic-light positioning after titlebar/button resets, alternating row heights and resizing. The automation's screen-sharing badge covers the traffic lights in screenshots, so screenshot evidence does not establish their exact position.

## Coverage boundary

The controller tests cover Escape, timed hover expansion and re-collapse, and continuous edge-scroll decisions. The native automation exposes a complete drag between two points, without a hold-at-target step. A held physical mouse/trackpad gesture for the 500 ms expansion, 300 ms re-collapse and re-entry cancellation cycle, Escape or prolonged edge scrolling has not been exercised. Pointer-based membership and reorder behavior above was exercised end to end, rather than inferred from the model tests.

## Motion stress verification

`TabStripMotionTests` hosts the actual `TabStrip` in an AppKit window, with its real window-local drag
controller. It records the animated geometry preferences that production hit testing consumes, including
intermediate positions. The matrix covers both layouts and pinned/ordinary folders:

1. Reverse disclosure three times while the neighboring header is still moving. Require intermediate
   positions, no endpoint overshoot or direct jump between endpoints, the correct final position, and
   stable tab instances and selection.
2. Hover until the real 500 ms task opens a folder, leave and return during the 300 ms close grace,
   leave long enough to animate the close, hover again, then drop onto a child's current bounds before
   the opening settles. Require correct hit testing, membership, pin state, selection and cleanup.

The signed Release was also exercised with six consecutive sidebar clicks, seven horizontal clicks,
four clicks on the active ordinary folder, and subsequent pin entry/exit in each layout. Counts,
disclosure state and the active page stayed correct. No disclosure or drop correctness defect was
reproduced; the production initializer only permits the native tests to share the strip's existing
drag controller. Display profiling results are assessed separately from these layout assertions.

These checks establish animated-layout continuity and live target synchronization. They do not measure
GPU/display frame pacing or a held physical gesture. Screenshot capture waits for a stable window; a
burst attempted during a 240 ms transition returned its first image after about 1 second, so those
images cannot establish frame-by-frame visual smoothness. The native-host tests are skipped when
system Reduce Motion is enabled rather than changing the user's accessibility preference.
