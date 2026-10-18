# Development notes

## Architecture

- `project.yml`: XcodeGen source of truth, app identity, entitlements, dependency versions.
- `Sources/Browser/BrowserModel.swift`: tabs and navigation commands.
- `BrowserTab.swift` and `PageDelegate.swift`: WebKit lifecycle and page requests.
- `BrowserWindow.swift`, `TabStrip.swift`, `WindowChrome.swift`: native layout.
- `History.swift`, `Session.swift`, `StoreFile.swift`: persistence.
- `Passwords.swift`: keychain storage with a Lisière-specific item marker.
- `Updates.swift`: Sparkle availability; placeholder keys disable updates.
- `Tests/BrowserTests`: inherited XCTest coverage.
- `Resources/Credits.rtf`, `NOTICE.md`, `LICENSE`: credits and licensing.

Build commands use the netrc package authorization provider for public dependencies, avoiding an unnecessary Xcode keychain prompt. No credentials are required to fetch Sparkle.

Ad hoc signatures have no Apple Team ID. As described in [Sparkle's integration guide](https://sparkle-project.org/documentation/), library validation otherwise rejects its framework at launch. `make build` sets the app-specific `BROWSER_ENTITLEMENTS` setting to `Config/Browser-Local.entitlements` only for the local build, retaining the app sandbox and other hardened-runtime protections. Developer ID archives keep `Config/Browser.entitlements`, with library validation enabled. Do not copy the local override into the release workflow.

`make smoke` starts the local app for five seconds and fails if it exits, then terminates only the process it started. This catches dyld failures; it does not replace visual or browsing checks.

The `Browser` Swift module and source directories retain their upstream names. Branding belongs in project.yml and visible strings; wholesale symbol renaming would make upstream merges harder.

Build output defaults to `~/Library/Developer/Xcode/DerivedData/Lisiere`, outside protected Documents/Desktop folders. This avoids a macOS folder-access prompt when dyld loads embedded frameworks. `DERIVED_DATA` can override the path.

## Daily workflow

```sh
git switch -c feature/short-description
make test
make build
```

Launch the Release app and verify changed behavior before committing. Generated projects and build output are ignored.

## Password save prompts

Register a pending password decision on `BrowserTab` before scheduling its native sheet. Main-frame navigation
actions and responses wait for that decision, and a page-requested popup close is deferred until the user answers.
Resume WebKit's original decision instead of cancelling and resubmitting a login request. JavaScript and requests
already running in the page are not suspended. Closing a tab or window explicitly cancels its sheet and pending
navigation; suspended tabs regain the ability to navigate when their web view is recreated.

The regression tests use real WebKit pages and native sheets with an in-memory password store. They cover Save,
Not Now, Never, password updates, immediate popup closure, background tabs and explicit user closure. On
2026-10-16, all 160 tests passed. The locally signed Release passed strict signature verification and startup smoke.
A separate validation bundle, retaining the Release sandbox and hardened runtime, also verified redirect and
popup-close flows using fictional credentials in a controlled HTTPS form. Real account sign-ins and distribution
signing were not exercised. The installed app and its profiles were not replaced.

## Synchronizing upstream

For a fresh clone, configure the read-only upstream remote once:

```sh
git remote add upstream https://github.com/athasdev/browser.git
git remote set-url --push upstream disabled
git config remote.pushDefault origin
```

Review upstream on a dedicated branch:

```sh
git fetch upstream
git switch -c maintenance/sync-athas
git log --oneline HEAD..upstream/main
git merge upstream/main
make test
make build
```

Preserve Lisière's identity, feed, attribution, and contribution policy during merges. Keep new upstream and dependency notices. Open a pull request against DaimHub/lisiere.

## Release boundaries

`make build` needs no Apple account. Public notarized releases, Sparkle signing, and passkeys need separate credentials or entitlements described in RELEASING.md. No credentials are included here.

The initial fork does not import Athas Browser data. Its distinct bundle identifier separates preferences, sandbox container, and WebKit data. Keep that separation when changing persistence.

## Interface icons

Hugeicons Free Stroke Rounded is provided by the MIT-licensed `iSapozhnik/hugeicons-swift` Swift package, pinned to 4.1.7 in `project.yml`. This is an unofficial Swift wrapper around the free Hugeicons catalog. Both app targets link it. `BrowserIcon.swift` owns semantic icon names and native template rendering; views use `Image(browserIcon:size:)` or `Label(_:browserIcon:)`, and AppKit uses `BrowserIcon.nsImage`. Copy package images before resizing so cached assets retain their original dimensions.

Application-owned menu actions use `Button(_:browserIcon:role:action:)` or the matching `Menu` initializer. Context menus and toolbar popups share `BrowserContextAction` data between native AppKit menus and SwiftUI keyboard/accessibility content. `browserMenu` supplies native popup rendering; `browserContextMenu` supplies right-click rendering. The transparent context-menu bridge only handles right-click and Control-click, leaving normal mouse interactions to the original view. AppKit owns icon tint for appearance, selection and disabled states. On macOS 27, explicitly request `NSMenuItem.preferredImageVisibility = .visible`; do not force a `.titleAndIcon` SwiftUI layout or bake foreground colors into menu pixels. The system-owned Settings command keeps its native scene routing. Reload uses Hugeicons `refresh` (RefreshIcon); Home and empty start-page tabs use `home01` (Home01Icon). Settings tabs use `Label(_:settingsIcon:)`: 24-point artwork centered in a 32-point transparent canvas prevents AppKit from enlarging each glyph to fill the toolbar slot.

Settings dropdowns containing icons use `BrowserIconPicker`, backed by `NSPopUpButton`. Its menu items and selection mark use Hugeicons template images directly, so mouse, keyboard and accessibility activation share the same native tinting. Do not put custom image labels inside SwiftUI `Picker`: their menu pixels can remain black in dark appearance. Text-only settings pickers retain their standard SwiftUI controls.

Home uses the bundled `BrowserHome01` template, imported from the official `Home01Icon` in `@hugeicons/core-free-icons` 4.3.5. The pinned Swift package's `home01` PDF still includes an old inner curve absent from the current icon. `BrowserIcon.nsImage` selects the updated artwork for Home actions, profile icons and new tabs in both tab layouts. Keep this override until the package artwork matches the current official icon.

Profile icon identifiers keep their historical raw values for on-disk compatibility. Only their `browserIcon` presentation changes. Favicons, mascots, Dock artwork and macOS-owned window controls keep their own artwork. Both builds include `Resources/Brand/LICENSE-hugeicons.txt`; no Pro assets are bundled.

## Profile appearance

`ProfileWindowController` attaches the physical window to the active profile's `AppearanceStore` and detaches it before switching or closing. The store applies the native appearance immediately and updates all windows currently displaying that profile when its theme changes. Parked profiles keep their page appearance but cannot recolor a window that now displays another profile. System clears the explicit window appearance. Keep `ProfileBrowserWindow.preferredColorScheme` too: SwiftUI's hosting layers and the glass background need it alongside the native window update.

System mode resolves a concrete SwiftUI color scheme from [`NSApplication.effectiveAppearance`](https://developer.apple.com/documentation/appkit/nsapplication/effectiveappearance) and observes its changes. Passing nil after an explicit dark theme can leave SwiftUI's hosting appearance dark until Settings opens. Resolve each profile's workspace palette from its own store too, so an outgoing System profile cannot inherit the incoming profile's forced theme. Website appearance remains separate.

Validation on 2026-10-17: the native-window round-trip regression failed before the fix. Coverage includes explicit light/dark round trips, System with separate light websites, live application appearance changes, parked profiles, multiple windows, detachment, and private windows. Native Release checks cover switching without opening Settings. Physical trackpad input was not exercised; the keyboard commands use the same profile controller as swipes.

## Toolbar customization

`ToolbarSettings` uses the horizontal preview as its editor. Select an individual button to move it left or right, or select the group icon to move the entire group. Option-Left and Option-Right invoke the same actions. Buttons inside a group move only among their siblings; use Move Out of Group before moving them elsewhere. The selected entry stays visible as the preview scrolls. Grouping, separation, adding, removal and Restore Default all update the same per-profile layout immediately.

Toolbar customization has no drag sources, drop targets, drag handles or vertical reorder list. `ReorderDropDelegate` remains owned by the horizontal and vertical tab layouts. Profile and Address remain required standalone controls, and the existing per-profile storage format is unchanged.

Validation on 2026-10-17: 216 XCTest tests passed, including 14 toolbar layout tests. The Release build and strict signature verification passed. A separate copy of the Release binary, with an isolated bundle identifier and the Release sandbox/hardened runtime retained, passed startup smoke. Native checks covered left/right buttons, Option-arrow shortcuts, group movement, child movement, grouping, separation, adding/removing buttons, required controls, both edge limits, horizontal scrolling, layout persistence after relaunch, sheet reopening, Restore Default, and light/dark appearance. Native secondary button tint stays independent of custom profile accents for readable labels. The installed application was not replaced.

## Split view

Split view displays exactly two existing `BrowserTab` instances in a native horizontal split view.
Open it from All Actions > Split View, from an inactive tab's context menu, or with Control-Command-S
(new tab). Control-Command-Right Arrow focuses the other pane. The active pane has a checked header
and accent outline; the shared toolbar, address field and page commands target that pane.

The two tabs form one outlined card in both layouts: stacked in the sidebar and side by side in the
horizontal strip. Their order matches the left and right panes. Each member retains its own focus,
close button, hover preview and context menu. The active member has a tinted fill; the shared outline
identifies the pair. Grouping alone never changes stored tab order, and exiting split restores the
ordinary cards. Dragging either member moves the joined card as a unit. Pane outlines use the same
12-point outside corner geometry as the page container, with straight edges at the native divider.

Dragging the native divider resizes both pages, with a 180-point minimum per pane. Removing a pane
or explicitly exiting split view keeps both tabs open. Closing a displayed split tab keeps its partner
selected. Selecting or opening another tab parks the split: its joined card remains, and selecting
either member restores both panes with the same divider proportion. All Actions > Split View > Return
to Split View also reopens it. Closing a parked member dissolves that pair without changing the current
page. Each profile retains its own split while switching profiles in the same window; private windows
only use their own in-memory WebKit store. Visible pages are excluded from background suspension;
parked pages can suspend normally, and returning restores both members together.

Split presentation is window-local and is not persisted across app restarts. The existing session
store still saves the two ordinary tabs and their history. `PageDelegate` recovers either visible
page after a WebKit process termination. Pointer activation observes native events without consuming
them, and `BrowserWebView` updates the active pane when keyboard/accessibility focus changes.

Validation on 2026-10-17: 233 XCTest tests passed. Coverage includes independent page navigation,
history, form state and zoom; native host attachment across split transitions; tab closure and session
replacement; joined-card ordering, unit reordering and bulk closure; profile/private cookie isolation;
keyboard focus; and visible-page recovery after WebKit termination. The Release build, strict signature
verification and startup smoke passed using dedicated Derived Data and an isolated QA bundle identifier,
with the Release sandbox and hardened runtime retained. The installed application was not replaced.

Native Release checks covered light/dark appearance, sidebar/horizontal joined cards, both active
corner outlines, page/toolbar focus, retained form input, exiting split, bulk closure after a joined
card, profile round trips and private windows. Divider resizing was verified through its accessibility
value. Continuous physical divider dragging and tab-card dragging remain unverified; card reorder
semantics are covered by XCTest. Full VoiceOver traversal and distribution/notarization were not tested.
Private tab layout was changed through its context menu: the existing View-menu layout shortcut does
not update private-window preferences.

Follow-up validation on 2026-10-17: 240 XCTest tests passed after preserving parked split pairs.
Regressions cover selecting other tabs, restoring both suspended members, closing or ungrouping a
parked pair without changing the current page, and restoring the native divider proportion. Release
build, strict signatures and isolated startup smoke passed. Native Release checks confirmed that
sidebar and horizontal cards remain joined while another tab is open, and selecting either member
restores both pages, form input and divider width. Opening a new tab and Return to Split View also
preserved the pair. The installed application was not replaced.

## Pinned tabs and named groups

Pin a tab from its context menu or Tabs > Pin Tab (Shift-Command-P). Pins occupy the leading
icon section in the horizontal strip and the top icon grid in the sidebar. They have no close
control; ordinary, bulk, keyboard and page-requested tab closure all go through BrowserModel and
leave them open. Unpin before closing. Window closure and app quit retain their existing session
behavior. Pinning does not exempt an inactive page from the existing idle/memory-pressure policy;
media, visible split panes, popups and their openers keep their existing suspension safeguards.

Create a group from the tab area's context menu or a tab's Move to Group > New Group action.
Group headers toggle collapse and expose name/color editing, adding a tab, ordering and ungrouping.
Dropping a local tab on a group header assigns it to that group; the menu provides the same action
without dragging. Ungrouping never closes a page. Empty groups remain available for later use.
Names and counts identify groups independently of their seven native semantic colors.

Pins stay first even when grouped. A group with both pinned and ordinary pages has a header in
each section; both headers edit the same group and share its collapsed state. Selecting a hidden
tab through keyboard navigation expands its group. Duplicate tabs and child tabs inherit the
group but start unpinned. Ordinary card dragging stays within the same pin/group section; moving
between groups uses a header drop or the menu. Split pages keep their existing content and focus:
only pages in the same pin/group section can share a joined card. Sidebar pins always use single
icons so the grid remains compact.

Pins use softly filled favicon tiles with a stronger active state. The sidebar has up to three
tiles per row; the final row stretches to fill its width. A custom layout preserves each tab's
view identity across row changes. The horizontal strip uses the same treatment with compact,
fixed-width tiles. Each pin area scrolls independently and leaves room for ordinary tabs.

TabSession stores pin state and group identity; WindowSession stores names, colors, group order
and collapse state. Missing fields in older sessions default to unpinned/ungrouped. Restoration
normalizes orphaned memberships and preserves the selected tab while leaving background pages
suspended. SessionStore observes metadata-only edits as well as page changes. These values follow
the existing per-profile, per-window session lifecycle and private-window non-persistence.
Suspended pins restore available favicons asynchronously from the existing disk cache without
loading a WebKit page or making a network request. Private pins never read persistent icons.

Bookmark names may be null, missing, empty or whitespace. The bar and start page display unnamed
bookmarks as icons, while menus, search, tooltips and accessibility retain a host/address label.
Renaming never replaces an empty name with that fallback. Existing bookmark IDs and URLs remain
unchanged. Both the bar and start-page favorites expose Rename.

Validation on 2026-10-17: 257 XCTest tests passed. Coverage includes protected closure paths,
pin suspension/history restoration, deferred popup closure, stable group ordering, split pairs
across organization boundaries, collapsed groups, legacy sessions, metadata-only autosave,
nullable bookmark names, tile layout at narrow widths, and cached pin icons without page loading.
The Release build, strict signature verification and isolated startup smoke passed, retaining
the sandbox and hardened runtime. Native checks covered five pins in both layouts, light/dark
sidebar tiles, active states without close controls, group creation/editing/collapse/ungrouping,
menu-based membership changes, unnamed bookmarks, split view across a pin boundary, and session
restoration including cached icons. The installed application was not replaced.

Automated native drag attempts did not confirm header drops; moving between groups by menu was
verified. Physical drag-and-drop and full VoiceOver traversal remain manual validation paths.


Follow-up validation on 2026-10-18: tab and folder moves use the window-local gesture described in
[the drag verification notes](design/toolbar/PINS-DRAG-VERIFICATION.md). Drag a folder header before or
after another folder to reorder its entire section in either layout; dropping over an expanded folder's
children also positions the folder as a unit. Both pinned and ordinary sections share the persisted group
order. Tab drops can insert into another group without changing pin state. The previous OS payload path
and its automated-drag limitation no longer apply. Dropping a folder in the empty sidebar or horizontal
space after the add button moves it to the end, preserving its contents and metadata; occupied targets
take precedence over the background. Collapsed folders open after a 500 ms site-drag hover in both
layouts, with a cancellable delay and no membership change before release. Folders opened by hovering
close 300 ms after exit, with the pending close cancelled on re-entry. Outside movement keeps the
original deadline; cancellation or an invalid release restores immediately, while a successful drop
keeps the target open. Their whole visible section counts as inside, and previously open folders remain
open. Release pointer drops are verified;
the timed opening/re-collapse cycle is covered by asynchronous controller tests rather than physical automation.
285 tests pass. Folder disclosure now uses a shared 240 ms smooth transition for content, neighboring
sections and pinned viewport sizing in both layouts; Reduce Motion disables it. Transient outgoing
child bounds cannot accept a drop into a collapsed folder.

Native motion regressions now host the real TabStrip and its drag controller in an AppKit window.
They inspect intermediate bounds during rapid reversals and timed hover/exit/re-entry/drop sequences
in both layouts with pinned and ordinary sites. See the motion stress section in the drag verification
notes for the distinction between animated-layout checks and display frame pacing.

The rendering follow-up separates drag feedback from changing hit-test bounds and the floating preview
from geometry resolution. It also defers closed context menus, collects only the requested hover-card
anchor, and reuses immutable SwiftUI icon templates without sharing mutable AppKit images. Continuous
pointer/disclosure tests measured 13.5–21.0% lower process CPU in the local native host; this does not
establish a display frame rate. See the verification notes for the workload and measurement limits.
