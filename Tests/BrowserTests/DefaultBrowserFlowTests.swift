import XCTest
@testable import Browser

/// Every mutation uses a fake. Running this suite must never change the developer's default browser.
@MainActor
final class DefaultBrowserFlowTests: XCTestCase {
    private let identifier = "io.github.daimhub.lisiere"

    private func model(_ system: FakeDefaultBrowserSystem) -> DefaultBrowser {
        DefaultBrowser(system: system, bundleIdentifier: identifier)
    }

    func testOpeningAndRefreshingSettingsNeverRequestsAChange() {
        let system = FakeDefaultBrowserSystem()
        let browser = model(system)
        XCTAssertEqual(browser.status, .unknown)
        browser.refresh()
        browser.refresh()
        XCTAssertEqual(browser.status, .notDefault)
        XCTAssertTrue(system.requests.isEmpty)
        XCTAssertEqual(system.settingsOpenCount, 0)
    }

    func testBothSchemesAreRequiredAndExternalChangesAreRefreshed() {
        let system = FakeDefaultBrowserSystem()
        let browser = model(system)
        system.handlers["https"] = identifier
        browser.refresh()
        XCTAssertEqual(browser.status, .partial)
        XCTAssertFalse(browser.isDefault)
        system.handlers["http"] = identifier
        browser.refresh()
        XCTAssertTrue(browser.isDefault)
        system.handlers["https"] = "another.browser"
        browser.refresh()
        XCTAssertEqual(browser.status, .partial)
        system.handlers["http"] = "another.browser"
        browser.refresh()
        XCTAssertEqual(browser.status, .notDefault)
        XCTAssertTrue(system.requests.isEmpty)
    }

    func testMissingHandlersAndMissingIdentityNeverCompareEqual() async {
        let system = FakeDefaultBrowserSystem()
        system.handlers = [:]
        let browser = DefaultBrowser(system: system, bundleIdentifier: nil)
        browser.refresh()
        XCTAssertEqual(browser.status, .unknown)
        XCTAssertFalse(browser.isDefault)
        await browser.makeDefault()
        XCTAssertEqual(browser.notice, .failed)
        XCTAssertTrue(system.requests.isEmpty)

        let knownBrowser = model(system)
        knownBrowser.refresh()
        XCTAssertEqual(knownBrowser.status, .unknown)
        system.handlers["http"] = identifier
        knownBrowser.refresh()
        XCTAssertEqual(knownBrowser.status, .partial)
    }

    func testAlreadyDefaultDoesNotRequestAgain() async {
        let system = FakeDefaultBrowserSystem()
        system.handlers = ["http": identifier, "https": identifier]
        let browser = model(system)
        await browser.makeDefault()
        XCTAssertTrue(browser.isDefault)
        XCTAssertTrue(system.requests.isEmpty)
    }

    func testOneConfirmationWhenMacOSChangesBothSchemes() async {
        let system = FakeDefaultBrowserSystem()
        system.onSet = { _ in system.handlers = ["http": self.identifier, "https": self.identifier] }
        let browser = model(system)
        await browser.makeDefault()
        XCTAssertEqual(system.requests, ["http"])
        XCTAssertTrue(browser.isDefault)
        XCTAssertFalse(browser.isRequesting)
        XCTAssertNil(browser.notice)
    }

    func testSeparateSchemeChangesAreVerified() async {
        let system = FakeDefaultBrowserSystem()
        system.onSet = { scheme in system.handlers[scheme] = self.identifier }
        let browser = model(system)
        await browser.makeDefault()
        XCTAssertEqual(system.requests, ["http", "https"])
        XCTAssertTrue(browser.isDefault)
        XCTAssertNil(browser.notice)
    }

    func testOnlyTheMissingSchemeIsRequested() async {
        for existing in ["http", "https"] {
            let system = FakeDefaultBrowserSystem()
            system.handlers[existing] = identifier
            system.onSet = { scheme in system.handlers[scheme] = self.identifier }
            let browser = model(system)
            await browser.makeDefault()
            XCTAssertEqual(system.requests, [existing == "http" ? "https" : "http"])
            XCTAssertTrue(browser.isDefault)
        }
    }

    func testCancellationStopsWithoutAnotherPrompt() async {
        for error in [NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError),
                      NSError(domain: NSOSStatusErrorDomain, code: -128),
                      NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [
                        NSUnderlyingErrorKey: NSError(domain: NSOSStatusErrorDomain, code: -128)
                      ])] {
            let system = FakeDefaultBrowserSystem()
            system.onSet = { _ in throw error }
            let browser = model(system)
            await browser.makeDefault()
            XCTAssertEqual(system.requests, ["http"])
            XCTAssertEqual(browser.notice, .cancelled)
            XCTAssertEqual(browser.status, .notDefault)
            XCTAssertFalse(browser.isRequesting)
        }
    }

    func testDecliningSecondSchemePreservesPartialState() async {
        let system = FakeDefaultBrowserSystem()
        system.onSet = { scheme in
            if scheme == "https" { throw CancellationError() }
            system.handlers[scheme] = self.identifier
        }
        let browser = model(system)
        await browser.makeDefault()
        XCTAssertEqual(system.requests, ["http", "https"])
        XCTAssertEqual(browser.status, .partial)
        XCTAssertEqual(browser.notice, .cancelled)
        XCTAssertFalse(browser.isRequesting)
    }

    func testPermissionFailureIsNotReportedAsCancellation() async {
        let system = FakeDefaultBrowserSystem()
        system.onSet = { _ in throw NSError(domain: NSOSStatusErrorDomain, code: -54) }
        let browser = model(system)
        await browser.makeDefault()
        XCTAssertEqual(system.requests, ["http"])
        XCTAssertEqual(browser.notice, .failed)
        XCTAssertFalse(browser.isDefault)
        XCTAssertFalse(browser.isRequesting)
    }

    func testCompletionWithoutChangedAssociationIsNotSuccessOrAnotherPrompt() async {
        let system = FakeDefaultBrowserSystem()
        let browser = model(system)
        await browser.makeDefault()
        XCTAssertEqual(system.requests, ["http"])
        XCTAssertEqual(browser.notice, .notCompleted)
        XCTAssertFalse(browser.isDefault)
        // A delayed system update, observed when the app becomes active, clears the stale notice.
        system.handlers = ["http": identifier, "https": identifier]
        browser.refresh()
        XCTAssertTrue(browser.isDefault)
        XCTAssertNil(browser.notice)
    }

    func testInFlightRequestRejectsDuplicateClicksAndSettingsNavigation() async {
        let system = FakeDefaultBrowserSystem()
        let browser = model(system)
        system.onSet = { _ in
            XCTAssertTrue(browser.isRequesting)
            browser.refresh() // App activation can arrive before the completion callback.
            await browser.makeDefault()
            browser.openSystemSettings()
            XCTAssertEqual(system.requests.count, 1)
            XCTAssertEqual(system.settingsOpenCount, 0)
            system.handlers = ["http": self.identifier, "https": self.identifier]
        }
        await browser.makeDefault()
        XCTAssertEqual(system.requests, ["http"])
        XCTAssertTrue(browser.isDefault)
        XCTAssertFalse(browser.isRequesting)
    }

    func testVerifiedSuccessWinsOverAnErrorFromMacOS() async {
        let system = FakeDefaultBrowserSystem()
        system.onSet = { _ in
            system.handlers = ["http": self.identifier, "https": self.identifier]
            throw NSError(domain: NSOSStatusErrorDomain, code: -54)
        }
        let browser = model(system)
        await browser.makeDefault()
        XCTAssertTrue(browser.isDefault)
        XCTAssertNil(browser.notice)
    }

    func testSystemSettingsFallbackNeverSetsAnAssociation() {
        let system = FakeDefaultBrowserSystem()
        let browser = model(system)
        system.canOpenSettings = false
        browser.openSystemSettings()
        XCTAssertEqual(browser.notice, .settingsUnavailable)
        system.canOpenSettings = true
        browser.openSystemSettings()
        XCTAssertNil(browser.notice)
        XCTAssertEqual(system.settingsOpenCount, 2)
        XCTAssertTrue(system.requests.isEmpty)
        system.handlers = ["http": identifier, "https": identifier]
        browser.refresh()
        XCTAssertTrue(browser.isDefault)
    }
}

@MainActor
private final class FakeDefaultBrowserSystem: DefaultBrowserSystem {
    var handlers = ["http": "another.browser", "https": "another.browser"]
    var requests: [String] = []
    var onSet: ((String) async throws -> Void)?
    var canOpenSettings = true
    var settingsOpenCount = 0

    func handlerIdentifier(for scheme: String) -> String? { handlers[scheme] }

    func setDefault(for scheme: String) async throws {
        requests.append(scheme)
        try await onSet?(scheme)
    }

    func openSettings() -> Bool {
        settingsOpenCount += 1
        return canOpenSettings
    }
}
