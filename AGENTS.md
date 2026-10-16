# Lisière contributor guidance

## Identity and licensing

- This is David Nikolic's personal project at `DaimHub/lisiere`.
- Preserve AGPL-3.0-or-later, Athas attribution, upstream Git history, and third-party notices.
- Product: Lisière. Build product/scheme: `Lisiere`. Bundle ID: `io.github.daimhub.lisiere`.
- The Swift module and directories remain `Browser` intentionally to simplify upstream merges.
- Do not accept the Athas CLA on the user's behalf. This fork uses AGPL contributions without a separate CLA.

## Architecture and interface

- Preserve native SwiftUI/AppKit/WebKit patterns and BrowserChrome layout values unless a redesign is requested.
- Keep navigation and tab state in BrowserModel/BrowserTab, page callbacks in PageDelegate, and persistence in existing stores.
- Use Product Design for UI work and inspect the built native app. Do not substitute web prototypes for native screens.
- Do not touch another installed browser's profile, credentials, bookmarks, or active windows.

## Validation

- `make test`: upstream XCTest suite in a locally signed Debug host without sandbox/hardened runtime, for XCTest injection and the deliberate WebKit process termination test. These overrides apply only to tests; Release retains both protections.
- `make build`: locally signed Release. Verify with `codesign --verify --deep --strict`.
- Check user-facing changes in the Release app. Report unverified account, hardware, entitlement, and distribution paths when relevant.
- Never commit build output, generated projects, browser profiles, signing assets, or credentials.
- Keep Sparkle pointed at the fork and disabled until its own keys are configured. Passkeys require Apple's approval for this fork's App ID.

## Git

- `origin` is `DaimHub/lisiere`; `upstream` is `athasdev/browser`.
- Verify the personal account before GitHub writes. Do not change globally active GitHub accounts or Git identity.
- Preserve unrelated work. Consult docs/DEVELOPMENT.md before syncing upstream.
