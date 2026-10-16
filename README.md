# Lisière

A native macOS browser built with SwiftUI and WebKit. Lisière is David Nikolic's independent, open-source fork of [Browser by Athas](https://github.com/athasdev/browser).

The name evokes the edge of a forest: a place to begin exploring. The initial fork preserves the native interface and browser behavior while establishing its own identity and development workflow.

## Develop locally

Requires macOS 26 or later, Xcode 26 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen). Sparkle 2.10.0 is resolved through Swift Package Manager.

```sh
git clone https://github.com/DaimHub/lisiere.git
cd lisiere
brew install xcodegen
make build
make test
make run
```

`make build` creates an ad hoc signed Release app at `~/Library/Developer/Xcode/DerivedData/Lisiere/Build/Products/Release/Lisiere.app`. This is a local development build, not a notarized distribution. `make test` runs the upstream XCTest suite in a locally signed Debug host without the app sandbox or hardened runtime. This supports XCTest injection and the test that deliberately terminates a WebKit process. Release builds retain both protections.

Build output stays in Xcode's standard Library location so launching embedded frameworks does not require access to a protected Documents or Desktop folder. Override it with `DERIVED_DATA=/your/build/path` when needed.

Open `Lisiere.xcodeproj` after `make generate` to work in Xcode. Use the `Lisiere` scheme. The Swift module and source directories retain the upstream `Browser` name to keep future merges focused.

## What is included

- Horizontal and vertical tabs, tab suspension, and session restoration.
- Bookmarks, history, downloads, page search, and per-site zoom.
- Private windows, tracker blocking, and site permissions.
- Default browser support and keychain-backed password features inherited from upstream.

Passkeys require Apple's browser entitlement and a matching provisioning profile. Automatic updates remain disabled until Lisière has its own Sparkle signing key. See [RELEASING.md](RELEASING.md).

## Independent identity

- Repository: [DaimHub/lisiere](https://github.com/DaimHub/lisiere).
- Display name: **Lisière**; build product: `Lisiere.app`.
- Bundle identifier: `io.github.daimhub.lisiere`.
- Update feed: this repository's releases, never Athas's feed.
- Preferences, website data, history, and the keychain item marker are separate from Athas Browser. This fork does not import or modify an existing Browser profile.

See [CONTRIBUTING.md](CONTRIBUTING.md), [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md), and [CHANGELOG.md](CHANGELOG.md) for development guidance.

## License and attribution

Copyright (C) 2026 Athas. Lisière modifications Copyright (C) 2026 David Nikolic and contributors.

Lisière is licensed under **GNU AGPL version 3 or later (AGPL-3.0-or-later)**. The original [LICENSE](LICENSE) is preserved unchanged. See [NOTICE.md](NOTICE.md) for provenance and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for dependency notices. The app bundles the license and notices, with credits in its About panel.

This is an independent fork, not an official Athas release. Athas retains the rights to its original work. Contributors retain the rights to their contributions. No Athas CLA or copyright assignment is required for contributions to Lisière.

Lisière is provided without warranty, as described in the license. When distributing a binary, provide the complete corresponding source for that version under the AGPL; the release workflow includes a source archive alongside the app.
