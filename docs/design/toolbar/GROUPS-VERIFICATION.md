# Groups, drag support and All Actions — 2026-10-16

This extends `c663c99` on `codex/customizable-toolbar`. The original checkout and unrelated work remain untouched. Product Design used the existing native toolbar and editor as the visual target.

## Automated checks

`make test DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/Lisiere-Toolbar"` passed 193 tests with zero failures. Thirteen toolbar tests cover legacy migration, malformed records, arbitrary groups, separation, moving groups/children between parents, insertion indices, rejecting invalid/self moves, per-profile persistence/copying, narrow presentation, automatic Downloads, Home, and native drag image/pasteboard creation.

The native row test checks that each NSTableCellView exposes its text/image outlets, generates a nonempty drag image and supplies the exact local row ID. Drag/drop follows AppKit's [NSOutlineView data-source contract](https://developer.apple.com/documentation/appkit/nsoutlineviewdatasource), also checked against the installed SDK headers.

`make build` succeeded. The built Release and isolated QA copy passed `codesign --verify --deep --strict`. The inherited ProfileAccent actor-isolation warning remains outside this change. Release retains the existing sandbox/hardened-runtime protections and local signing entitlements.

Local logs: `/tmp/lisiere-toolbar-groups-final-tests.log`, `/tmp/lisiere-toolbar-groups-build.log`.

## Native QA

A separately signed Release copy (`io.github.daimhub.lisiere.toolbarqa`) isolates exploratory settings from the user's profiles. Confirmed via native accessibility state and inspected captures:

- All Actions lists Profiles, Back, Forward, Reload, Address & Search, New Tab, Home, New Private Window, History, Downloads, Bookmarks Bar, Settings and Customize Toolbar. Unavailable navigation actions are disabled.
- Customize Toolbar opens the native editor from the menu.
- Navigation children reorder with arrows; the entire navigation group separates into individual buttons.
- The grouping menu combines Reload and New Tab; both appear in one shared rounded toolbar segment and in the editor preview.
- Custom groups/order persist across QA relaunch.
- Row controls align consistently; groups and indented children remain distinguishable.
- The user manually tested drag/drop in the native QA Release and confirmed it works, while reporting a laggy feel. The follow-up uses reusable native cells (keeping controls/constraints intact) and AppKit gap insertion feedback. The saved layout changes only on drop; scrolling and hover feedback reuse native row controls.

## Installed Release

Installed the final Release at `/Applications/Lisiere.app` after the user closed the previous app normally. The installed bundle matches the built Release and passes `codesign --verify --deep --strict`.

The previous app and data were backed up at `~/Library/Application Support/Lisiere Release Backups/toolbar-groups-2026-10-16-213004`. All 10,589 readable data files matched their pre-install hashes before launch.

Native relaunch restored the four existing tabs and the selected New Tab. The existing custom order migrated intact: Home, Profile, the Back/Forward/Reload group, Address, New Tab, Private Window, History, Downloads, Bookmarks and Settings. All Actions was appended. The menu lists all controls, and its Downloads action opened the native downloads popover. Customize Toolbar opened the final editor with reusable native rows and the correct groups.

The inspected [installed editor capture](groups-settings.jpg) also shows the Profile/Home group present during the user's concurrent interaction. The editor is closed and the installed browser remains open. No test layout was applied to the user's profile by the agent.

## Evidence limits

Physical drag/drop has user-confirmed functional evidence. The subjective smoothness of the follow-up optimization has not yet been confirmed by the user. Model and native-cell tests alone do not establish a physical drag gesture. Full VoiceOver, account authentication, passkeys, Developer ID distribution and Sparkle updates are outside this change.
