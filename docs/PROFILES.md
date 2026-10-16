# Independent browser profiles

Use the profile menu beside the address field or **Profiles** in the menu bar. Switching changes the profile inside the current window. Each window retains an independent set of tabs for each visited profile; switching back restores those same live pages, including unsaved form fields. Another window already showing that profile is not focused or modified. With no browser window open, choosing a profile opens one. New normal/private windows use the focused window's profile. External links use the frontmost normal window; with none open, they use the last selected profile.

Swipe horizontally with two fingers over the vertical sidebar or horizontal tab strip to move through profiles. One gesture changes one profile, wrapping at either end. Vertical sidebar scrolling, page gestures and scroll momentum do not trigger a switch. The menu and **⌥⌘[ / ⌥⌘]** also provide previous/next navigation. With one profile, scrolling keeps its existing behavior.

## Create and edit

**Profiles > Manage Profiles** opens the dedicated **Profiles** tab in the standard Settings window. It lets you create a profile, edit its name/icon or delete it. Choose one of twelve native icons. Names are trimmed, unique without regard to case and limited to 40 characters. Editing a name or icon never changes its identity or data paths.

A new profile can start empty, or copy settings, bookmarks and tab addresses from an existing profile. The copy is a snapshot, with its own UUID and stores; later changes do not propagate in either direction. Cookies, sign-ins, passwords, history, downloads, site permission grants, cached files and WebKit form/back-forward interaction state are not copied. The copied tabs start fresh connections. If the copied restore preference is off, saved tabs are available through **History > Reopen All Windows from Last Session**.

## Data boundaries

| Data | Scope |
| --- | --- |
| Cookies, HTTP disk/memory cache, localStorage, IndexedDB, Cache Storage, service workers and other WebKit website data | Persistent WebKit store per profile |
| History, open/closed windows, tabs and back/forward interaction state | Per profile |
| Bookmarks and bookmark bar visibility | Per profile |
| Saved passwords and password settings | Per profile; Keychain security domain separates identical site/account pairs |
| Download list and prompts | Per profile; files remain at their chosen destinations |
| Site permissions and site zoom | Per profile |
| Site icons, memory/disk icon caches | Per profile; icon requests never carry cookies or URL credentials |
| Search engine, new-tab page, tab layout and session restoration | Per profile |
| Tracker-blocking preference and site exceptions | Per profile, with separately identified compiled rules |
| Passkeys and OS credential providers | Managed by macOS, not partitioned by this browser |
| Default browser registration, software updates and OS permissions | Application/OS-wide |

Settings has an explicit profile selector. Its controls and website-data clearing act on that profile. Switching the selected profile resets sensitive password and site-data UI state. Profiles separate browser-managed state; they are not macOS accounts, separate filesystem sandboxes or an anonymity service.

Each profile visited in a private window gets a fresh `WKWebsiteDataStore.nonPersistent()`. Switching profiles stays private and returns to the same temporary pages when switching back. Tabs/pop-ups within it share that temporary store; other private windows and normal profiles do not. Private windows keep no persistent history, session, permissions, zoom or password manager, and never restore on restart. Search/layout preferences, bookmarks and downloads belong to their originating profile.

## Existing installations and persistence

The initial **Personal** profile keeps `WKWebsiteDataStore.default()`, existing history/session files, existing defaults, icon cache and original password namespace. Nothing is copied, reset or imported from Athas Browser.

New profiles use immutable UUIDs with `WKWebsiteDataStore(forIdentifier:)`. Their history, session and icon cache live under `Profiles/<UUID>/` in Lisière's Application Support directory. Their preferences use a dedicated UserDefaults suite. Keychain items use a profile-specific security domain, which is part of Keychain's unique key; merely labeling items would not separate identical credentials.

`Profiles.plist` atomically records names, icons, IDs, selection and pending deletions. Older entries without icons decode with the default icon. An unreadable or unsupported registry fails closed. Each profile has its own `SessionStore`; pending windows survive quitting before they have appeared. The scene creates its window controller once after SwiftUI installs its state, avoiding spare WebViews during profile-name or selection updates. The controller retains one BrowserModel per visited profile and never retargets a WebView’s data store. Only the active model is registered for external URL routing.

Session files distinguish visible windows from parked profile sessions, linked by a stable window UUID. Restart restores visible windows; switching within one reclaims its parked tabs without creating extra windows. Older session files decode without these optional fields. Closing a window releases every retained model, and unvisited parked tabs remain available through History. Copying a profile includes its parked tabs as fresh addresses, without the window linkage or interaction state.

## Explicit deletion

Deletion requires the native destructive confirmation, names the target profile and lists affected data. At least one available profile must remain. All normal/private windows retaining the target profile, including windows currently showing another profile, must be closed and its downloads finished or cancelled. A durable pending-deletion record blocks reopening while deletion runs.

The app removes its passwords, compiled tracker rules, site icons, WebKit website data, named WebKit store, files and preferences, then drops the registry entry. The initial default WebKit store is cleared through the public data-removal API; its directory is not manually removed. Its owned legacy files/keys are deleted individually so app-wide settings and the profile registry remain intact. Files already downloaded are kept. Late queued history/session writes are disabled before removing files.

If deletion fails or the app stops midway, the unavailable profile offers **Retry Delete**. Retrying requires confirmation; destructive work never silently resumes at launch.

## Validation

`make test` covers registry migration/persistence, icon persistence, name validation, corruption handling, data boundaries, copying without credentials/form state, deletion guards/retry, late-write prevention, Keychain separation and gesture filtering. Live WebKit tests use `Tests/Fixtures/profile_site.py`, a loopback-only server, for cookies, localStorage, IndexedDB, Cache Storage, service workers and numbered cacheable HTTP responses. They check two persistent profiles, fresh private windows, pop-ups, duplicate/suspended/restored tabs and clearing one store without changing the other.

Tests clear their synthetic website records. XCTest can retain empty WebKit store objects until the host exits; physical named-store deletion is also checked in the native Release workflow. Recreating a WebView is distinct from restarting the app process.

For Release validation, use dedicated DerivedData and an isolated bundle/container, retaining the Release sandbox and hardened runtime. Do not overwrite `/Applications/Lisiere.app` or touch any other browser's data. Save `alpha` and `beta` at the same loopback origin in two profiles, restart the process, and verify distinct values, worker URLs and cache response numbers. Exercise empty/copy creation, icons, rename, settings/bookmark independence, both tab layouts, private windows, cancellation and actual deletion. Native event filtering tests do not prove physical trackpad behavior.

Public APIs: [named WebKit stores](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/init(foridentifier:)), [store removal](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/remove(foridentifier:completionhandler:)), and [AppKit gesture momentum](https://developer.apple.com/documentation/appkit/nsevent/momentumphase). Real account sign-ins, physical trackpad input, Developer ID, notarization and passkey entitlement approval require separate validation.

### Recorded local validation — 2026-10-16

The sandboxed ad hoc Release validation copy used its own bundle/container. Personal retained `alpha` and HTTP cache response 5 through process restarts. A copied Work profile inherited its bookmark, tab address and vertical layout but started with empty website storage; after saving `beta`, it retained that marker, its own worker and cache response 10 after restart. Removing Work's bookmark and changing its layout/search engine left Personal unchanged. Empty Research started with a blank tab, no bookmarks and its chosen icon.

Native checks covered both layouts, create/edit forms, profile-specific Settings, named clear-data confirmation/cancellation, normal/private session behavior, and deleting a closed seeded profile without restarting. Work disappeared from the registry and its owned directory was removed; Personal still returned `alpha` afterward. Release signature verification and startup smoke passed. No installed application or other browser's data was replaced. Physical two-finger trackpad verification and the distribution/account paths listed above remain outside this evidence.

### Same-window navigation correction — 2026-10-16

Validated on the integrated themes/mascots Release base `c06b7e5`, in the isolated `io.github.daimhub.lisiere.profiles-validation` container. Manage Profiles opened the standard SwiftUI Settings window (`com_apple_SwiftUI_Settings_window`) with seven tabs, including Profiles. General and Appearance remained accessible, with the profile selector and existing theme/mascot controls.

Native menu and Next Profile actions switched Personal/Research in `browser-AppWindow-1`, including the change between vertical and horizontal tab layouts. Returning to Personal preserved an unsaved form value and its separate `alpha` site data and HTTP cache response 5. A process restart restored one visible session plus its parked profile; returning to the parked profile did not create another window. A private Research-to-Personal switch retained `private-AppWindow-1` and private chrome. The profile control's 34-point height was visually checked against navigation/address controls in both layouts.

The integrated XCTest suite passed 164 tests. Added coverage includes the same NSWindow identity and window count, two windows on the same profile, live form and same-origin storage preservation, private switching, legacy session decoding, visible/parked restoration, deletion guards, pending-window ownership and copying parked tabs without ownership or interaction state. Release build and strict signature checks passed; the validation copy retained sandbox and hardened runtime. Physical trackpad input remains unverified; gesture filtering and the resulting window transition are covered in tests. No installed app was replaced.
