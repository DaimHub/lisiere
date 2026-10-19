# Tab split and window detachment verification

Validated on 2026-10-19, from `codex/tab-drag-split-detach`, based on `main` / `origin/main` at `23ac718`.
The integration checkout and `/Applications/Lisiere.app` were not modified.

## Automated checks

- Full Debug XCTest suite: **326 passed, zero failures or skips**.
- Final focused run: **29 passed, zero failures or skips**, including the additional suspended-tab transfer case, native page ownership, profile windows and suspension.
- Release build and `codesign --verify --deep --strict`: passed.
- `make smoke`: journey, restart and existing performance budgets passed with Reduce Motion off and on.
- QA copies retain sandbox and hardened runtime, with a separate bundle identifier and container.

Tests cover left/right selection, replacing a split pane without closing it, cancellation, toolbar and
window-edge rejection, screen coordinate conversion, pin/group metadata, private cookie isolation,
profile boundaries, pending password decisions, password message routing, suspended tabs, one-shot
scene requests, last-tab fallback, and the original WebView/form/history surviving transfer.

## Native Release checks

Using automated pointer drags in the isolated Release:

- Horizontal tabs: drop onto the left half creates the expected split.
- Vertical tabs: drop onto the right half creates the expected split.
- Detaching a split member creates another window with the same tab identifier; the source retains its other page.
- Form text survives splitting and both horizontal and vertical detachment.
- The final Release keeps the last normal and private tab visible after detachment, with the same identifier and entered text.
- A private tab opens in another private window and preserves its temporary session.
- A fresh split in the final Release displays both pages and the retained form value.
- The tab context menu exposes Move to New Window and the layout switch.

The last-tab native check exposed an outgoing SwiftUI host reclaiming its page during the transition
to a blank source tab. Production page hosts now verify their BrowserModel ownership before attaching.
A deterministic regression verifies that late updates and old-host disposal cannot steal the moved page.

## Evidence and limits

Dedicated build directory: `~/Library/Developer/Xcode/DerivedData/LisiereTabDragDetach`.
Final startup reports: `Validation/acceptance/{standard,reduced}`.
Final native QA app: `Validation/manual-final/Lisiere QA.app`.

Physical trackpad input, full-screen detachment, real-account sign-ins, Developer ID distribution,
notarization and passkeys were not exercised. Automated screen-placement tests include negative monitor
origins. These checks do not claim a frame-time guarantee. The feature remains on its isolated branch;
it has not been merged into main or installed over the personal application.
