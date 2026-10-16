# Lisière contributor guidance

## Identity and licensing

- This is David Nikolic's personal project at `DaimHub/lisiere`.
- Preserve AGPL-3.0-or-later, Athas attribution, upstream Git history, and third-party notices.
- Product: Lisière. Build product/scheme: `Lisiere`. Bundle ID: `io.github.daimhub.lisiere`.
- The Swift module and directories remain `Browser` intentionally to simplify upstream merges.
- Do not accept the Athas CLA on the user's behalf. This fork uses AGPL contributions without a separate CLA.

## Architecture and interface

- Use `BrowserIcon` (Hugeicons Free Stroke Rounded) for interface icons in SwiftUI and AppKit. Keep persisted `ProfileIcon` raw values stable; use `browserIcon` for rendering. Use `BrowserMenuLabel` or the icon-aware `Button` initializer in menus, `browserContextMenu` for native context-menu tint, and `Label(_:settingsIcon:)` for Settings tabs.
- Preserve native SwiftUI/AppKit/WebKit patterns and BrowserChrome layout values unless a redesign is requested.
- Always use the transparent `Mascot-*` artwork on the new-tab page, in both palettes and appearances. Do not add a background behind it or use the `Dock-*` icon variants there.
- Keep navigation and tab state in BrowserModel/BrowserTab, page callbacks in PageDelegate, and persistence in existing stores.
- Use Product Design for UI work and inspect the built native app. Do not substitute web prototypes for native screens.
- Do not touch another installed browser's profile, credentials, bookmarks, or active windows.

## Validation

- `make test`: upstream XCTest suite in a locally signed Debug host without sandbox/hardened runtime, for XCTest injection and the deliberate WebKit process termination test. These overrides apply only to tests; Release retains both protections.
- `make build`: locally signed Release. Verify with `codesign --verify --deep --strict`.
- Local ad hoc builds use Config/Browser-Local.entitlements for Sparkle library validation. Never use that exception for Developer ID releases. `make smoke` checks startup as well as signatures.
- Check user-facing changes in the Release app. Report unverified account, hardware, entitlement, and distribution paths when relevant.
- Never commit build output, generated projects, browser profiles, signing assets, or credentials.
- Keep Sparkle pointed at the fork and disabled until its own keys are configured. Passkeys require Apple's approval for this fork's App ID.

## Git

- `origin` is `DaimHub/lisiere`; `upstream` is `athasdev/browser`.
- `main` is the integration baseline. Before reusing an older worktree, fetch `origin` and compare its history with `origin/main`. Preserve pending work before updating, and integrate current `main` before building or installing a new version.
- Verify the personal account before GitHub writes. Do not change globally active GitHub accounts or Git identity.
- Preserve unrelated work. Consult docs/DEVELOPMENT.md before syncing upstream.
