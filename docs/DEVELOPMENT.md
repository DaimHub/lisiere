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

Ad hoc signatures have no Apple Team ID. As described in [Sparkle's integration guide](https://sparkle-project.org/documentation/), library validation otherwise rejects its framework at launch. `make build` selects `Config/Browser-Local.entitlements` only for the local build, retaining the app sandbox and other hardened-runtime protections. Developer ID archives keep `Config/Browser.entitlements`, with library validation enabled. Do not copy the local override into the release workflow.

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
