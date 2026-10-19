# Tab dragging between pages and windows

Validated on 2026-10-19 from `codex/tab-drag-split-detach`, integrated on top of main `122ffa5`.
This follow-up replaces the original last-tab fallback and adds transfers back into existing windows.

## Behavior

- A lightweight, mouse-transparent native panel follows the pointer in screen coordinates, including outside the source window.
- Dropping onto another compatible window's tab strip inserts the live tab. Dropping onto its page creates a left/right split.
- Windows must use the same profile and data store; a detached private window can return to its original private session.
- Moving the last tab closes the source window after adoption. It does not create a blank tab or an empty restorable window.
- Pointer hover does not move ownership; Escape clears both windows' previews without changing their tabs.
- Window hit testing respects the frontmost native window, including windows belonging to other applications.

## Automated checks

- Full Debug XCTest gate: **331 passed, zero failures or skips**.
- Four native-window regressions cover the floating panel outside the source bounds, preservation of focus,
  same-WebView round trips with form text, insertion into a target group, cancellation, cross-window split,
  incompatible-profile rejection, closing an emptied source and session persistence.
- The round-trip regression also waits for the floating panel to be displayed before verifying that it does not mask the destination.
- Existing coverage retains pin/group metadata, private cookie isolation, password decisions and routing,
  suspended-tab transfer, split membership, history and late page-host ownership.
- Release build, strict deep codesign verification, and startup/restart smoke with Reduce Motion off and on passed.
- Release and QA copies retain sandbox and hardened runtime; QA has an isolated identity and container.

An initial full run timed out in an existing animated-layout test; that test passed unchanged in isolation
and in the final full run. Another run exposed a fixed 600 ms setup wait in the group-collapse test.
That setup now waits for the group to open; the subsequent grace-period and cancellation assertions remain unchanged.

## Native Release inspection

Automated pointer drags in the isolated Release confirmed that detaching an existing page preserves its
identifier and entered form value. Repeated last-tab detachment closed each prior source window and
left the page visible in the destination. The Window menu contained only the surviving windows.

The external automation's cross-window attempt was not a valid foreground drop: temporary diagnostics
showed a different window above both QA windows at the requested screen points. The implementation
correctly did not drop through it. The positive cross-window path is therefore verified by the native
AppKit-window regression rather than claimed as a successful external Release gesture. The diagnostic
logging was removed before delivery.

## Evidence and limits

Dedicated build directory: `~/Library/Developer/Xcode/DerivedData/LisiereTabDragDetach`.
Full test result: `TestResults/Debug-20261019-171837.xcresult`.
Initial Release reports: `Validation/window-fixes/{standard,reduced}`.
Final clean-commit Release reports: `Validation/window-fixes-final/{standard,reduced}`.
Native inspection copy: `Validation/window-fixes-manual/Lisiere QA.app`.

Physical trackpad input, continuous visual tracking outside the window, foreground cross-window pointer
drops in the Release, full-screen transitions, real-account sign-ins, Developer ID distribution,
notarization and passkeys were not exercised. Screen-coordinate tests include negative monitor origins.
These checks do not claim a frame-time guarantee. The installation record and verified profile/session
backup are stored separately under `~/Library/Application Support/Lisiere Release Backups/`.
