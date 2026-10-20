import WebKit
import XCTest
import Synchronization
@testable import Browser

@MainActor
final class ProfileStoreTests: XCTestCase {
    private func fixture() -> (URL, UserDefaults) {
        let root = FileManager.default.temporaryDirectory.appending(path: "LisiereProfiles-\(UUID())")
        let suite = "LisiereProfilesTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        return (root, defaults)
    }

    func testInitialProfilePreservesLegacyPathsAndData() async throws {
        let (root, defaults) = fixture()
        let session = SessionSnapshot(windows: [WindowSession(tabs: [
            TabSession(url: URL(string: "https://example.com"), title: "Existing", interactionState: nil)
        ], selectedIndex: 0)])
        let file = StoreFile(url: root.appending(path: "Session.plist"))
        file.writeNow(try PropertyListEncoder.binary.encode(session))
        let originalBytes = file.readNow()
        defaults.set(["example.com": 1.5], forKey: "pageZoomLevels")
        let initialDataStore = WKWebsiteDataStore(forIdentifier: UUID())
        let profiles = ProfileStore(root: root, defaults: defaults, dataStoreFactory: { _ in initialDataStore })
        let context = try XCTUnwrap(profiles.context(for: BrowserProfile.initialID))
        XCTAssertEqual(profiles.directory(for: .initial), root)
        XCTAssertEqual(file.readNow(), originalBytes)
        XCTAssertEqual(context.zoomLevels.level(for: "example.com"), 1.5)
        XCTAssertEqual(context.session.snapshot, session)
        let browser = context.makeBrowser(downloads: DownloadManager())
        _ = context.session.attach(browser)
        XCTAssertEqual(browser.activeTab?.title, "Existing")
        XCTAssertTrue(browser.websiteDataStore === initialDataStore)
        context.prepareForDeletion()
    }

    func testRegistryRoundTripRenameSelectionAndInvalidNames() throws {
        let (root, defaults) = fixture()
        let profiles = ProfileStore(root: root, defaults: defaults)
        let work = try profiles.create(name: " Work ")
        XCTAssertThrowsError(try profiles.create(name: "work"))
        XCTAssertThrowsError(try profiles.create(name: "  "))
        XCTAssertThrowsError(try profiles.create(name: String(repeating: "x", count: 41)))
        try profiles.rename(work.id, to: "Research")
        try profiles.select(work.id)
        let reopened = ProfileStore(root: root, defaults: defaults)
        XCTAssertEqual(reopened.selectedID, work.id)
        XCTAssertEqual(reopened.name(work.id), "Research")
        XCTAssertEqual(reopened.context(for: work.id)?.browsingData.dataStore.identifier, work.id)
        XCTAssertEqual(profiles.context(for: work.id)?.browsingData.dataStore.identifier, work.id)
    }

    func testHistorySessionsPermissionsAndZoomDoNotCrossProfiles() async throws {
        let (root, defaults) = fixture()
        let profiles = ProfileStore(root: root, defaults: defaults)
        let a = try profiles.create(name: "A")
        let b = try profiles.create(name: "B")
        let first = try XCTUnwrap(profiles.context(for: a.id))
        let second = try XCTUnwrap(profiles.context(for: b.id))
        await first.history.waitUntilLoaded()
        await second.history.waitUntilLoaded()
        first.history.recordVisit(to: URL(string: "https://example.com")!, title: "A")
        first.zoomLevels.setLevel(1.5, for: "example.com")
        first.sitePermissions.setDecision(true, for: .camera, on: "example.com")
        XCTAssertTrue(second.history.visits.isEmpty)
        XCTAssertEqual(second.zoomLevels.level(for: "example.com"), 1)
        XCTAssertNil(second.sitePermissions.decision(for: [.camera], on: "example.com"))
        let browser = first.makeBrowser(downloads: DownloadManager())
        _ = first.session.attach(browser)
        browser.restoreSession(WindowSession(tabs: [TabSession(url: URL(string: "https://example.com"),
                                                              title: "A", interactionState: nil)], selectedIndex: 0))
        first.session.saveBeforeQuitting()
        first.history.saveNow()
        let reopened = ProfileStore(root: root, defaults: defaults)
        let restored = try XCTUnwrap(reopened.context(for: a.id))
        await restored.history.waitUntilLoaded()
        XCTAssertEqual(restored.history.visits.first?.title, "A")
        XCTAssertEqual(restored.session.snapshot.windows.first?.tabs.first?.title, "A")
        XCTAssertTrue(second.session.snapshot.windows.isEmpty)
        // An unvisited profile's pending windows must survive another quit.
        restored.session.saveBeforeQuitting()
        XCTAssertEqual(ProfileStore(root: root, defaults: defaults).context(for: a.id)?.session.snapshot.windows.count, 1)
        first.prepareForDeletion(); second.prepareForDeletion(); restored.prepareForDeletion()
    }

    func testMalformedRegistryFailsClosedWithoutOverwritingIt() throws {
        let (root, defaults) = fixture()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appending(path: "Profiles.plist")
        let bytes = Data("not a profile registry".utf8)
        try bytes.write(to: file)
        let profiles = ProfileStore(root: root, defaults: defaults)
        XCTAssertNotNil(profiles.loadError)
        XCTAssertNil(profiles.context(for: BrowserProfile.initialID))
        XCTAssertThrowsError(try profiles.create(name: "New"))
        XCTAssertThrowsError(try profiles.select(BrowserProfile.initialID, persistImmediately: false))
        profiles.saveBeforeQuitting()
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testDeferredSelectionDoesNotWaitForDiskAndCannotOverwriteLaterEdits() async throws {
        let (root, defaults) = fixture()
        let blockNextWrite = Mutex(false)
        let writeTimedOut = Mutex(false)
        let gate = DispatchSemaphore(value: 0)
        let entered = expectation(description: "Selection write reached the background queue")
        let file = StoreFile(url: root.appending(path: "Profiles.plist")) { data, url in
            let block = blockNextWrite.withLock { value in defer { value = false }; return value }
            if block {
                XCTAssertFalse(Thread.isMainThread)
                entered.fulfill()
                if gate.wait(timeout: .now() + 5) == .timedOut { writeTimedOut.withLock { $0 = true } }
            }
            try data.write(to: url, options: .atomic)
        }
        let profiles = ProfileStore(root: root, defaults: defaults, manifestFile: file)
        let a = try profiles.create(name: "A")
        let b = try profiles.create(name: "B")
        blockNextWrite.withLock { $0 = true }
        defer { gate.signal() }
        try profiles.select(a.id, persistImmediately: false)
        XCTAssertEqual(profiles.selectedID, a.id)
        await fulfillment(of: [entered], timeout: 2)
        XCTAssertFalse(writeTimedOut.withLock { $0 }, "The UI must return while storage is still blocked")
        try profiles.select(b.id, persistImmediately: false)
        XCTAssertEqual(profiles.selectedID, b.id)
        gate.signal()
        try profiles.rename(b.id, to: "Renamed B")
        let renamed = ProfileStore(root: root, defaults: defaults)
        XCTAssertEqual(renamed.selectedID, b.id)
        XCTAssertEqual(renamed.name(b.id), "Renamed B")
        try profiles.select(a.id, persistImmediately: false)
        profiles.saveBeforeQuitting()
        XCTAssertEqual(ProfileStore(root: root, defaults: defaults).selectedID, a.id)
    }

    func testDeferredSelectionFailurePreservesRegistryAndCanBeRetried() async throws {
        let (root, defaults) = fixture()
        let failWrites = Mutex(false)
        let file = StoreFile(url: root.appending(path: "Profiles.plist")) { data, url in
            if failWrites.withLock({ $0 }) { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        }
        let profiles = ProfileStore(root: root, defaults: defaults, manifestFile: file)
        let a = try profiles.create(name: "A")
        let original = try XCTUnwrap(file.readNow())
        failWrites.withLock { $0 = true }
        try profiles.select(a.id, persistImmediately: false)
        XCTAssertEqual(file.readNow(), original)
        XCTAssertEqual(file.lastFailure?.operation, .write)
        for _ in 0..<100 where profiles.persistenceFailure == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(profiles.persistenceFailure?.store, "profiles")
        XCTAssertEqual(profiles.persistenceFailure?.canRetry, true)
        failWrites.withLock { $0 = false }
        profiles.retryPersistence()
        XCTAssertNil(file.lastFailure)
        XCTAssertEqual(ProfileStore(root: root, defaults: defaults).selectedID, a.id)
        for _ in 0..<100 where profiles.persistenceFailure != nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(profiles.persistenceFailure)
    }

    func testDeletionRequiresClosedWindowsAndKeepsOtherProfileData() async throws {
        let (root, defaults) = fixture()
        let profiles = ProfileStore(root: root, defaults: defaults)
        let a = try profiles.create(name: "A")
        let b = try profiles.create(name: "B")
        defaults.set("shared", forKey: "bookmarks")
        let context = try XCTUnwrap(profiles.context(for: a.id))
        let browser = context.makeBrowser(downloads: DownloadManager())
        profiles.register(browser)
        do { try await profiles.delete(a.id); XCTFail("Deleted an open profile") }
        catch { XCTAssertTrue(error is ProfileStore.Failure) }
        XCTAssertFalse(try XCTUnwrap(profiles.profile(a.id)).pendingDeletion)
        profiles.unregister(browser)
        browser.releaseClosedWindow()
        await context.history.waitUntilLoaded()
        context.history.recordVisit(to: URL(string: "https://example.com")!, title: "A")
        try profiles.select(a.id, persistImmediately: false)
        try await profiles.delete(a.id)
        // Late save callbacks must not resurrect deleted files.
        context.history.saveNow()
        context.session.saveBeforeQuitting()
        XCTAssertNil(profiles.profile(a.id))
        XCTAssertNotEqual(profiles.selectedID, a.id)
        XCTAssertNotNil(profiles.profile(b.id))
        XCTAssertEqual(defaults.string(forKey: "bookmarks"), "shared")
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(profiles.directory(for: a)).path))
        XCTAssertNil(ProfileStore(root: root, defaults: defaults).profile(a.id))
    }

    func testSwitchingDoesNotRetargetExistingWindowsOrTheirSessions() throws {
        let (root, defaults) = fixture()
        let profiles = ProfileStore(root: root, defaults: defaults)
        let a = try profiles.create(name: "A")
        let b = try profiles.create(name: "B")
        let first = try XCTUnwrap(profiles.context(for: a.id)).makeBrowser(downloads: DownloadManager())
        let second = try XCTUnwrap(profiles.context(for: b.id)).makeBrowser(downloads: DownloadManager())
        first.open(URL(string: "about:blank")!)
        second.open(URL(string: "about:blank")!)
        let firstTab = first.activeTabID
        try profiles.select(a.id)
        try profiles.select(b.id)
        try profiles.select(a.id)
        XCTAssertEqual(first.activeTabID, firstTab)
        XCTAssertEqual(first.activeTab?.webView?.configuration.websiteDataStore.identifier, a.id)
        XCTAssertEqual(second.activeTab?.webView?.configuration.websiteDataStore.identifier, b.id)
        XCTAssertFalse(first.websiteDataStore === second.websiteDataStore)
    }

    func testInterruptedDeletionStaysUnavailableUntilExplicitRetry() async throws {
        let (root, defaults) = fixture()
        let profiles = ProfileStore(root: root, defaults: defaults)
        let a = try profiles.create(name: "A")
        let file = root.appending(path: "Profiles.plist")
        var manifest = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: file),
                                                                           format: nil) as? [String: Any])
        var rows = try XCTUnwrap(manifest["profiles"] as? [[String: Any]])
        rows[1]["pendingDeletion"] = true
        manifest["profiles"] = rows
        try PropertyListSerialization.data(fromPropertyList: manifest, format: .binary, options: 0).write(to: file)
        let reopened = ProfileStore(root: root, defaults: defaults)
        XCTAssertNil(reopened.context(for: a.id))
        XCTAssertThrowsError(try reopened.select(a.id))
        XCTAssertNotNil(reopened.profile(a.id))
        try await reopened.delete(a.id)
        XCTAssertNil(reopened.profile(a.id))
    }

    func testCannotDeleteLastProfile() async throws {
        let (root, defaults) = fixture()
        let profiles = ProfileStore(root: root, defaults: defaults)
        do { try await profiles.delete(BrowserProfile.initialID); XCTFail("Deleted the last profile") }
        catch { XCTAssertTrue(error is ProfileStore.Failure) }
        XCTAssertEqual(profiles.availableProfiles, [.initial])
    }
}
