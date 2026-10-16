# Validation — 2026-10-16

## Automated checks

- `make test DERIVED_DATA=/Users/davidnikolic/Library/Developer/Xcode/DerivedData/Lisiere-ProfileFade`: 196 tests, zero failures (46.416 seconds).
- After the final system-theme inheritance adjustment, ProfileWindowTests and ProfileAppearanceTests passed again: 11 tests, zero failures.
- Final `make build` succeeded for the locally signed Release. Both the build and `/Applications/Lisiere.app` passed `codesign --verify --deep --strict`; their executable SHA-256 hashes match.
- Release retains the sandbox and hardened runtime. The isolated QA copy uses a separate bundle ID and the Release's extracted entitlements. Sparkle remains unconfigured.

Logs: `/tmp/lisiere-profile-fade-test.log`, `/tmp/lisiere-profile-fade-final-tests.log`, `/tmp/lisiere-profile-fade-build-final.log`.

## Native app checks

A separate Release copy (`io.github.daimhub.lisiere.profilefadeqa`) exercised the native Profile menu and keyboard shortcuts with fictional profiles. Checked a light profile with vertical tabs and a dark profile with horizontal tabs, a new-tab page and a real WebKit page. Eight successive shortcut activations returned to the same visible page and selected tab. The private window retains its dark violet material and independent session.

Inspected captures: [light profile](perso-light.jpg), [dark profile with a web page](pro-web.jpg). These capture settled states, not a frame-by-frame animation recording. Physical two-finger trackpad feel and the system Reduce Motion setting were not exercised; the existing swipe recognition tests passed and both entry points use the same controller. Reduce Motion selects an identity transition in the view.

## Installation and preservation

The normal app was quit before replacement. Its previous signed bundle and data were saved in `~/Library/Application Support/Lisiere Release Backups/profile-fade-2026-10-16-220742`. All 10,629 regular data-file SHA-256 hashes matched before relaunch. Normal runtime writes after relaunch are outside that byte-for-byte check.

The installed Release reopened Perso with its new tab, bookmarks, mascot and toolbar. Switching to Pro restored its existing tab in the same physical window. Switching back restored Perso. No account action was taken. The installed app remains open on Perso; the isolated QA app is closed.

This is local ad hoc validation, not Developer ID/notarization or physical trackpad certification.
