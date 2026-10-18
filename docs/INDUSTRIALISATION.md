# Reliability and release acceptance

This work strengthens existing browsing and persistence. It does not add product features. The entry point is
`make validate`: tooling tests, the complete Debug and optimized Release XCTest suites, then a protected Release
build and native browsing/restart acceptance in two accessibility configurations.

## Data guarantees

- StoreFile distinguishes absent files from read/decode failures. Unreadable history and sessions remain byte
  for byte intact, including on quit and after late asynchronous callbacks. Unsupported session versions are
  rejected. Existing unversioned sessions still decode.
- Atomic writes retain the previous file on failure. The latest failed payload can be retried. A native error
  banner identifies the affected store and explains recovery. Restoring a corrupt file requires reopening the
  app; explicit Clear All History remains able to remove corrupt history at the user's request.
- Invalid bookmark JSON is preserved instead of being replaced after an empty load fallback.
- Clear History awaits loading and flushes the result before completing. Deleting a profile disables queued
  writes before removing its files. There are no new hidden backups which could resurrect cleared data.
- Session saves debounce for two seconds; history saves debounce for one second. Ordinary quit flushes both.
  A force quit or power loss can lose changes still in memory, and continuous edits can extend the debounce
  interval. Atomicity prevents partial replacement; it is not a guarantee against physical disk failure.
- Unit cases cover malformed/future files, denied directory writes, a simulated out-of-space error, retry of
  the latest snapshot, deletion races, and explicit erasure. A separate process uses the real Swift StoreFile
  under eight SIGKILL timings; every surviving snapshot must be complete. This does not simulate power failure.

## Blocking and lifecycle

The complete tracker list is compiled by WebKit. Facebook pixel filters avoid unsupported alternation.
The shield reports installed protection, loading, or failure instead of just reporting the preference. Initial
main-frame navigation waits for installation. Rapid exception changes cannot publish an obsolete ready state.
The Release journey tests network enforcement and a site exception with the production list plus one synthetic
loopback tracker; no external tracking endpoint is contacted.

Termination observers are owned by their stores and released when a profile disappears. Local OSLog categories
`storage`, `webkit`, and `lifecycle` contain operations and error codes, never page contents, URLs, cookies or
credentials. A profile-switch signpost supports local Instruments analysis. No telemetry or diagnostic upload
is added to the app.

## Protected Release protocol

The runner verifies strict signing, sandbox, hardened runtime and absence of `get-task-allow`. It copies the
compiled app, gives the copy a unique `io.github.daimhub.lisiere.qa.*` identifier, removes URL/document handler
registration and update keys, and signs it locally. It retains the executable UUID and records the original
binary SHA-256, source commit, dirty flag, OS and Xcode version. The same compiled application code runs with
the local library-validation exception already required by ad hoc Sparkle builds. This is not a Developer ID
distribution validation.

The acceptance driver is gated by both that QA namespace and explicit process environment variables. Normal bundles
ignore it. Its server binds only to loopback. Downloaded fixtures stay inside the QA container. App defaults,
Keychain descriptions and security domains are isolated; production keeps its legacy Keychain domain.
QA bundles and synthetic containers are retained for inspection and are never installed over `/Applications`.

The journey covers redirects, back/forward, form submission, tabs, folders, split, close/reopen, close during a
slow load, a disconnected response and recovery, rapid profile changes, private isolation, downloaded bytes,
and repeated tab creation/destruction. A separate process checks tabs, folders, bookmarks, history, persistent
cookies, local storage, profile isolation, deletion and durable history clearing. The entire journey repeats
with an app-local Reduce Motion environment, leaving the user's system preference unchanged.

XCTest additionally covers deliberate WebKit process termination and recovery, permissions, password decisions,
private state, profile deletion, and native geometry. Its test host deliberately disables sandbox/hardening for
XCTest injection and enables testability, in both configurations. Only the subsequent `make build` and acceptance
copies are production-protected. Hosted Release tests must never be mistaken for the shipping app validation.

The native animation fixtures explicitly enable motion in their own SwiftUI environment, even if the CI runner
has Reduce Motion enabled. Their intermediate-position, reversal, drag-target and tab-identity assertions still
run in both Debug and Release. The protected Release journey separately exercises reduced motion. No test changes
the user's system accessibility preference. After every `make test`, the xcresult summary must report a nonempty
run with every test passed: skipped tests, expected failures, missing counts or inconsistent results fail the gate.
The machine-readable summary is retained alongside its xcresult bundle.

## Performance protocol

`journey.json` records time to the first native window, 20,000-page address-index construction, the 95th percentile
of 60 deterministic address queries, 40 profile switches, folder state mutations and four batches of 25 tab
creation/closure cycles. Each closed tab must be released. Resident memory samples cover the app process only,
not all WebKit child processes. Model timings do not measure physical input-to-display latency or frame rate.

The first local reference on an Apple M3 Pro/macOS 27/Xcode 27.1 measured address queries around 28 ms p95,
profile changes around 2.1 ms p95 and under 1 MiB RSS growth over 100 tab cycles. Conservative automated limits
are in `scripts/performance-budgets.json`: 100 ms for address queries, 20 ms for profile switching, 2 ms mean for
folder mutations and 64 MiB app RSS growth. These are regression tripwires, not a universal performance promise.
Do not loosen a failing budget without inspecting retained measurements on the relevant runner.

## Delivery gates and remaining external validation

CI retains xcresult bundles, logs, measurements, provenance and dSYMs. The tag workflow calls the same CI workflow
on the tagged commit before accessing signing secrets or publishing. Sparkle's exact version is read from its
own package block, and prerelease names never enter the numeric bundle version. The exported executable also
runs the isolated journey before notarization and publication. Releases include symbols, checksums and provenance.

XcodeGen is checked against `.xcodegen-version`. Swift dependencies remain exactly pinned in project.yml.
Xcode and SDK versions are recorded; local macOS 27 and CI macOS 26 are separate acceptance environments.

Developer ID identity, notarization, Sparkle keys and a real interrupted Sparkle update need the project's
distribution credentials and a signed prior release. Passkeys require Apple's entitlement; Touch ID, camera,
microphone, real account flows, Intel runtime, physical trackpad dragging and complete VoiceOver navigation
require their own equipment or manual acceptance. Record these as unverified when not exercised. Never infer
their success from an ad hoc QA bundle, an accessibility-tree snapshot, or green XCTest alone.
