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

## Toolbar customization

`ToolbarSettings` uses the horizontal preview as its editor. Select an individual button to move it left or right, or select the group icon to move the entire group. Option-Left and Option-Right invoke the same actions. Buttons inside a group move only among their siblings; use Move Out of Group before moving them elsewhere. The selected entry stays visible as the preview scrolls. Grouping, separation, adding, removal and Restore Default all update the same per-profile layout immediately.

Toolbar customization has no drag sources, drop targets, drag handles or vertical reorder list. `ReorderDropDelegate` remains owned by the horizontal and vertical tab layouts. Profile and Address remain required standalone controls, and the existing per-profile storage format is unchanged.

Validation on 2026-10-17: 216 XCTest tests passed, including 14 toolbar layout tests. The Release build and strict signature verification passed. A separate copy of the Release binary, with an isolated bundle identifier and the Release sandbox/hardened runtime retained, passed startup smoke. Native checks covered left/right buttons, Option-arrow shortcuts, group movement, child movement, grouping, separation, adding/removing buttons, required controls, both edge limits, horizontal scrolling, layout persistence after relaunch, sheet reopening, Restore Default, and light/dark appearance. Native secondary button tint stays independent of custom profile accents for readable labels. The installed application was not replaced.
