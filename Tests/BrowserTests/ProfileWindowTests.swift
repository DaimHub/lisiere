import AppKit
import WebKit
import XCTest
@testable import Browser

@MainActor
final class ProfileWindowTests: XCTestCase {
    private var owners: [ProfileWindowController] = []
    private var profiles: ProfileStore!
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ProfileWindowTests-\(UUID())")
        suite = "ProfileWindowTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        profiles = ProfileStore(root: root, defaults: defaults)
    }

    override func tearDown() async throws {
        owners.forEach { $0.close() }
        for profile in profiles.profiles {
            profiles.context(for: profile.id)?.prepareForDeletion()
            if !profile.isInitial { defaults.removePersistentDomain(forName: ProfileStore.defaultsDomain(for: profile.id)) }
        }
        owners = []
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    private func owner(_ id: UUID, privateMode: Bool = false, store: ProfileStore? = nil) throws -> ProfileWindowController {
        let owner = try ProfileWindowController(profiles: store ?? profiles, profileID: id, isPrivate: privateMode)
        owners.append(owner)
        return owner
    }

    func testSwitchKeepsTheSameNSWindowAndRestoresExactTabsWithoutStealingAnotherWindow() throws {
        let a = try profiles.create(name: "A")
        let b = try profiles.create(name: "B")
        let first = try owner(a.id)
        let other = try owner(b.id)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: true)
        let otherWindow = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        first.connect(window)
        other.connect(otherWindow)
        let original = first.browser
        original.addTab()
        let tabIDs = original.tabs.map(\.id)
        let originalView = original.activeTab?.webView
        let otherTab = other.browser.activeTabID
        let count = NSApp.windows.count

        first.switchBy(1)
        XCTAssertEqual(first.browser.profileID, b.id)
        XCTAssertTrue(first.browser.window === window)
        XCTAssertNil(original.window)
        XCTAssertFalse(first.browser === other.browser)
        XCTAssertEqual(first.browser.websiteDataStore.identifier, b.id)
        XCTAssertEqual(original.websiteDataStore.identifier, a.id)
        XCTAssertTrue(other.browser.window === otherWindow)
        XCTAssertEqual(other.browser.activeTabID, otherTab)
        XCTAssertEqual(NSApp.windows.count, count)

        first.switchBy(-1)
        XCTAssertTrue(first.browser === original)
        XCTAssertTrue(first.browser.activeTab?.webView === originalView)
        XCTAssertEqual(first.browser.tabs.map(\.id), tabIDs)
        XCTAssertTrue(first.browser.window === window)
        XCTAssertEqual(NSApp.windows.count, count)
    }

    func testRestartRestoresOnePhysicalWindowAndItsParkedProfileOnDemand() throws {
        let a = try profiles.create(name: "A")
        let b = try profiles.create(name: "B")
        let first = try owner(a.id)
        first.browser.addTab()
        first.browser.addTab()
        first.switchTo(b.id)
        first.browser.addTab()
        let ownerID = first.id
        let contextA = try XCTUnwrap(profiles.context(for: a.id))
        let contextB = try XCTUnwrap(profiles.context(for: b.id))
        XCTAssertEqual(contextA.session.snapshot.windows.count, 0)
        XCTAssertEqual(contextA.session.snapshot.parkedWindows.first?.tabs.count, 3)
        XCTAssertEqual(contextB.session.snapshot.windows.count, 1)
        contextA.session.saveBeforeQuitting()
        contextB.session.saveBeforeQuitting()
        first.close()

        try profiles.select(a.id) // A Settings selection must not open the parked profile in an extra window.
        let restarted = ProfileStore(root: root, defaults: defaults)
        XCTAssertEqual(restarted.defaultWindowProfileID, b.id)
        let restored = try owner(b.id, store: restarted)
        XCTAssertEqual(restored.id, ownerID)
        XCTAssertEqual(restored.additionalWindows, 0)
        XCTAssertEqual(restored.browser.tabs.count, 2)
        XCTAssertFalse(try XCTUnwrap(restarted.context(for: a.id)).session.hasPendingWindows)
        restored.switchTo(a.id)
        XCTAssertEqual(restored.browser.tabs.count, 3)
        XCTAssertEqual(restored.id, ownerID)
        restored.switchTo(b.id)
        XCTAssertEqual(restored.browser.tabs.count, 2)
        restored.close()
        restarted.context(for: a.id)?.prepareForDeletion()
        restarted.context(for: b.id)?.prepareForDeletion()
    }

    func testPrivateSwitchUsesFreshSeparateStoresAndNeverPersistsParkedSessions() throws {
        let a = try profiles.create(name: "A")
        let b = try profiles.create(name: "B")
        let first = try owner(a.id, privateMode: true)
        let original = first.browser
        first.switchTo(b.id)
        XCTAssertTrue(first.browser.isPrivate)
        XCTAssertNil(first.browser.history)
        XCTAssertNil(first.browser.passwords)
        XCTAssertFalse(first.browser.websiteDataStore === original.websiteDataStore)
        XCTAssertEqual(profiles.context(for: a.id)?.session.snapshot, SessionSnapshot())
        XCTAssertEqual(profiles.context(for: b.id)?.session.snapshot, SessionSnapshot())
        first.switchTo(a.id)
        XCTAssertTrue(first.browser === original)
        first.close()
        XCTAssertTrue(original.tabs.isEmpty)
        XCTAssertNil(original.profileWindow)
    }

    func testParkedLiveProfilesCannotBeDeletedAndClosingReleasesEveryModel() async throws {
        let a = try profiles.create(name: "A")
        let b = try profiles.create(name: "B")
        let first = try owner(a.id)
        let original = first.browser
        first.switchTo(b.id)
        let second = first.browser
        do { try await profiles.delete(a.id); XCTFail("Deleted a retained session") }
        catch { XCTAssertEqual(error.localizedDescription, ProfileStore.Failure.openWindows.localizedDescription) }
        first.close()
        XCTAssertTrue(original.tabs.isEmpty)
        XCTAssertTrue(second.tabs.isEmpty)
        XCTAssertTrue(profiles.context(for: a.id)?.session.snapshot.parkedWindows.isEmpty == true)
        XCTAssertEqual(profiles.context(for: a.id)?.session.reopenableWindows.count, 1)
    }

    func testCopyIncludesParkedTabsWithoutSharingTheirWindowIdentity() throws {
        let a = try profiles.create(name: "A")
        let b = try profiles.create(name: "B")
        let first = try owner(a.id)
        first.browser.addTab()
        first.switchTo(b.id)
        let copy = try profiles.create(name: "Copy", copying: a.id)
        let context = try XCTUnwrap(profiles.context(for: copy.id))
        let saved = try XCTUnwrap(context.session.snapshot.windows.first)
        XCTAssertEqual(saved.tabs.count, 2)
        XCTAssertNil(saved.profileWindowID)
        XCTAssertTrue(saved.tabs.allSatisfy { $0.interactionState == nil })
        XCTAssertTrue(context.session.snapshot.parkedWindows.isEmpty)
        XCTAssertEqual(context.browsingData.dataStore.identifier, copy.id)
    }

    func testSwitchDoesNotConsumeAnotherWindowsPendingRestore() throws {
        let a = try profiles.create(name: "A")
        let b = try profiles.create(name: "B")
        let file = StoreFile(url: try XCTUnwrap(profiles.directory(for: b)).appending(path: "Session.plist"))
        file.writeNow(try PropertyListEncoder.binary.encode(SessionSnapshot(windows: [
            WindowSession(tabs: [TabSession(url: nil, title: "", interactionState: nil),
                                 TabSession(url: nil, title: "", interactionState: nil)],
                          selectedIndex: 1, profileWindowID: UUID())
        ])))
        let first = try owner(a.id)
        first.switchTo(b.id)
        XCTAssertEqual(first.browser.tabs.count, 1)
        XCTAssertTrue(profiles.context(for: b.id)?.session.hasPendingWindows == true)
        let other = try owner(b.id)
        XCTAssertEqual(other.browser.tabs.count, 2)
        XCTAssertNotEqual(first.id, other.id)
    }
}
