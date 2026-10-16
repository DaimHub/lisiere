# Contributing to Lisière

Lisière is maintained at [DaimHub/lisiere](https://github.com/DaimHub/lisiere), independently of [Athas Browser](https://github.com/athasdev/browser).

## Development

1. Install the requirements in the README and run `make generate`.
2. Create a branch for a focused change.
3. Follow the existing SwiftUI, AppKit, and WebKit patterns. Keep browser behavior owned by the existing models and delegates.
4. Run `make test` and `make build`.
5. For interface changes, launch the Release app and check the changed interaction, keyboard access, and both tab layouts as applicable.
6. Open a pull request against **DaimHub/lisiere**, describing the behavior change and validation.

Do not commit generated Xcode projects, DerivedData, personal browser data, signing certificates, private keys, or credentials. Update documentation and the changelog when behavior or build requirements change.

## Licensing

By submitting a contribution for inclusion in Lisière, you license that contribution under **AGPL-3.0-or-later**. You retain copyright. No separate CLA, copyright assignment, or proprietary relicensing grant is requested.

Only contribute material you have the right to license. Identify third-party sources and preserve their notices. Keep the original Athas attribution and the unmodified AGPL text.

The original Athas CLA is archived at [docs/upstream/CONTRIBUTOR_LICENSE_AGREEMENT.md](docs/upstream/CONTRIBUTOR_LICENSE_AGREEMENT.md) for provenance. It is not Lisière's contribution agreement. Contributions sent separately to Athas are subject to that project's own contribution process.
