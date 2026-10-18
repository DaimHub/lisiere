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
drag controller. The animation implementation is unchanged.

Instruments' Animation Hitches template was attached to the exact isolated QA Release process. During
the timed horizontal burst (18 header clicks in 4.496 s), it recorded 15 hitch events, each 8.33–12.50 ms.
During the sidebar burst (16 header clicks and a pin dragged out, 5.040 s), it recorded 69 events, each
8.33–16.67 ms. These measurements establish small rendering delays under profiling; they do not establish
perfect frame pacing or an uninstrumented frame rate. The complete mixed-action recordings also include
captures, menus and layout changes: 194 events in the 61.012 s horizontal recording (maximum 95.83 ms),
and 95 in the 30.928 s sidebar recording (maximum 33.33 ms). Only events within the recording window and
belonging to the QA process are counted. Exported event totals outside that window are excluded.

No specific animation or hit-testing fault was isolated from these traces. The native-host tests cover
the timed hover/re-entry path; the sidebar collapsed-folder drop occurred after profiling stopped and
is functional evidence only. The local trace exports and phase summary are retained under the ignored
`.build/folder-motion/` directory.

The native-host checks establish animated-layout continuity and live target synchronization; display
profiling is a separate measurement with the limits above. Neither exercises a held physical gesture.
Screenshot capture waits for a stable window; a
burst attempted during a 240 ms transition returned its first image after about 1 second, so those
images cannot establish frame-by-frame visual smoothness. The native-host tests are skipped when
system Reduce Motion is enabled rather than changing the user's accessibility preference.

## Rendering optimization follow-up

Folder timing, easing, layout and spring-loading behavior remain unchanged. The rendering path now
separates the continuously updated hit-test selection from the visual indicator (target identity and
insertion side). Moving a target's bounds no longer invalidates every consumer of selection while its
visual state stays the same. Crossing an animated child midpoint still changes the insertion marker,
and release always uses the latest geometry. Unchanged pointer and scrolling values are not republished.
Hit testing filters lazily, avoiding an intermediate candidate array for every pointer sample.

The floating preview has its own SwiftUI view, separate from anchor resolution. Hover-card anchors are
collected only for the requested preview rather than for every tab during every layout pass. Context
menu actions are built on demand in a separate view; the native AppKit menu still reads its live factory
when opened. SwiftUI icon templates reuse a bounded, evictable cache keyed by icon and size, preserving
their image identity across updates. AppKit callers continue to receive independent mutable images.

The continuous-motion regression hosts the real strip, moves a pointer 120 times with 8 ms pauses and
reverses disclosure every 20 samples, then checks cancellation, tab identity, membership and selection.
The same test was run against baseline `6ab98a5` and the optimization, in the same Debug host/configuration:

| Native scenario | Baseline process CPU | Optimized process CPU | Reduction |
| --- | ---: | ---: | ---: |
| Sidebar, ordinary tabs | 908 ms | 785 ms | 13.5% |
| Sidebar, pins | 912 ms | 788 ms | 13.6% |
| Horizontal, ordinary tabs | 1053 ms | 836 ms | 20.6% |
| Horizontal, pins | 1032 ms | 815 ms | 21.0% |

These are local, single-pass process CPU measurements, including framework/background work, not a GPU
frame-rate or hitch-duration benchmark. They show less work in the combined drag/disclosure workload;
they do not prove elimination of the display hitches recorded above. The simpler stationary-header
hover test did not show a consistent CPU improvement, so its timings are not presented as a gain.

Additional regressions verify that 240 animated header frames leave visual observers quiet while
hit testing stays current, child midpoints still update insertion feedback, closed menus do not build
actions during native layout changes, hover geometry appears and disappears with the requested preview,
and cached SwiftUI icons remain independent of mutable AppKit images. The full 290-test suite passed,
followed by the added continuous-motion regression in all four configurations.

The signed Release was checked in both layouts with 24 consecutive folder-header clicks, pin exit and
re-entry into a collapsed folder. Folder counts, pin state and the active page remained correct. The
folder's context menu changed from Collapse Group to Expand Group after use, confirming live action
state. The same 24-click bursts used 2.85 s versus 2.27 s of process CPU in the sidebar and 2.98 s versus
2.59 s horizontally. These coarse `ps` measurements include the surrounding idle/capture interval;
automation cadence also differed (sidebar 4.55/3.78 s, horizontal 3.99/4.57 s). They support reduced
rendering work but are not controlled frame-pacing measurements. No new Instruments hitch-count
comparison was made, and the held physical hover cycle remains outside this automation's capabilities.

## Instruments remeasurement after the rendering optimization

On 2026-10-18, Instruments 27.1 was attached to the exact isolated, signed Release process built from
`d309343`. The fixture was a 900 × 472 pt window with five pins in Recherche and one active ordinary
tab in Travail. Both layouts used the existing 240 ms disclosure animation. Pointer input timestamps
were recorded separately from the trace; only hitch events for the attached PID inside the actual
recording window were counted. Each action window includes 500 ms after the last input to capture its
finishing animation. Counts describe these short samples, not a benchmark across machines.

| Layout and action | Input duration | Hitches | Largest hitch |
| --- | ---: | ---: | ---: |
| Horizontal, 24 rapid header clicks | 4.342 s | 14 | 8.33 ms |
| Sidebar, 24 rapid header click inputs | 4.168 s | 18 | 8.33 ms |
| Horizontal, drag a pin out | 0.095 s | 1 | 8.33 ms |
| Sidebar, drag a pin out | 0.076 s | 4 | 41.67 ms |
| Horizontal, drop into a collapsed folder | 0.082 s | 6 | 41.67 ms |
| Sidebar, drop into a collapsed folder, dedicated capture | 0.127 s | 1 | 8.33 ms |
| Sidebar, eight ordinary-folder reversals after settling | 1.649 s | 13 | 33.33 ms |

The first two traces used Hitches and Frame Lifetimes. The dedicated sidebar capture used Hitches
alone. The first sidebar collapsed-folder drop fell outside the recording and is excluded; the
dedicated capture above covers the complete action and settling window. The sidebar rapid inputs
started the ordinary-folder burst while its header was still moving after pin expansion, so input
count is not a claim that every click toggled that moving header. The separate eight-click burst
used the settled header and returned it to its initial state. The sidebar rapid and drag-out windows
overlap slightly; their counts must not be summed as independent events.

The 41.67 ms horizontal drop prompted a targeted Hitches + Time Profiler capture with three repetitions.
All three complete action windows were inside the recording. They reported respectively 1, 3 and 4
hitches, with maxima of 8.33, 33.33 and 33.33 ms. The main-thread samples were spread across SwiftUI,
AttributeGraph and runtime work. The inclusive `BrowserModel.dropTab` stacks accounted for 5, 4 and 3 ms
of sampled time in those windows; these are nested stack weights, not additive costs. No specific
new application bottleneck or drop/disclosure correctness defect was isolated, so no speculative
animation or model change was made. Occasional 33–42 ms display delays remain measurable.

These captures do not establish an improvement over the earlier Instruments run: instrumentation,
input cadence, workload and background load differ. The native Release checks confirmed pin counts,
membership, disclosure state and active-page preservation after the drops. The full suite passed
291 tests, including the real-host continuous pointer/disclosure and hover/exit/re-entry regressions.
The held physical hover/trackpad path remains unmeasured by the pointer automation.

Raw traces and timestamped XML/JSON evidence are retained locally under the ignored
`.build/folder-motion/remeasure-*` paths. `remeasure-summary.json` marks coverage explicitly and
`remeasure-cpu-summary.json` contains the targeted stack weights. Trace archives can contain process
environment data; only the measured results belong in source control. For follow-up captures, prefer
short Hitches recordings; adding Frame Lifetimes substantially increased post-processing time here.

## Drag completion hitch investigation

A follow-up on 2026-10-18 used SwiftUI (including layout tracing), Hitches and Time Profiler together.
The fixture and 500 ms settling window remained the same. Four repetitions in each layout moved a
loose pin into the collapsed Recherche folder, moved one pin back out and collapsed the folder again.
The eight drop windows were checked against the recording bounds and overlapping events were deduplicated.

Two sources of unnecessary work were isolated:

- `activeTab` and `splitTabs` looked up their pages through the observable `tabs` array. Reordering that
  array therefore invalidated page and toolbar consumers although their selection had not changed.
  The sidebar trace contained 22 `BrowserWindow` body updates: eight caused by the drops and 14 driven
  by environment updates. Storing identity-checked selection projections removed the eight drop-driven
  updates; the corresponding trace contained only the 14 environment updates. A regression test failed
  with the old implementation for both ordinary and split selection, then passed with the fix.
- Selection isolation alone did not remove the late display stalls. A Hitches + Time Profiler recording
  still showed repeated 33–50 ms hitches about 240 ms after release, at the end of the move animation.
  The drag preview used a native material backdrop, and `withAnimation` at drop completion also animated
  its removal. The preview now uses the native window background color and an animation-free transaction.
  It disappears when the pointer releases, while the actual tab/folder move keeps its existing animation.
  This also applies to folder previews. It avoids creating a moving native backdrop and delaying cleanup
  until the tab animation completes.

The following captures use Hitches + Time Profiler, without SwiftUI's detailed graph tracing. Each row
contains eight drops and their finishing animation. `Selection only` is an intermediate build with the
first fix but the old preview; `Final` includes both changes.

| Build and layout | Hitch events | Total hitch duration | Largest hitch | Hitches over 25 ms |
| --- | ---: | ---: | ---: | ---: |
| Selection only, horizontal | 45 | 625.00 ms | 50.00 ms | 5 |
| Final, horizontal | 18 | 150.00 ms | 8.33 ms | 0 |
| Final, sidebar | 26 | 241.67 ms | 25.00 ms | 0 |

These short traces support the preview cleanup change; they do not establish a universal frame-time
ceiling or a reduction in total CPU time. Input and accessibility snapshot cadence differ between runs,
background load is uncontrolled, and a new process was used for the final build. The detailed SwiftUI
captures are diagnostic evidence for invalidations, not directly comparable hitch benchmarks. Their
maxima were 16.67/50.00 ms before the changes and 41.67/50.00 ms with selection isolation alone
(horizontal/sidebar). The combined correction is what removed the recurring late spikes in the final
samples. Physical held-hover and trackpad gestures remain outside this automation's coverage.

The native checks retained the active Example Domain page, pin membership/counts and collapsed state.
The selection tests also cover close/restore, invalid IDs, selection changes and continued observation
of the selected page's own properties. The native-host motion tests cover rapid reversals and continuous
pointer movement against animated geometry, including spring-open/exit/re-entry/drop.

Evidence is retained locally in the ignored `.build/folder-hitch-cause/` directory: timestamped
`phases.json`, `*-hitch-summary.json`, `*-swiftui-summary.json`, `*-cpu-summary.json`, and the original
traces. Only sanitized summaries belong in source control; trace metadata may contain process environment.

Final validation: 294 XCTest tests passed with zero failures (116.881 s), including all four native-host
motion tests. The Release used for the final captures passed strict signature verification. The extra
cold-baseline comparison was interrupted by the Mac locking, so it is not included in the results.
