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

    func testPasswordFieldMessagesFollowTheDetachedPageOwner() async throws {
        let profile = try profiles.create(name: "Password routing")
        let source = try owner(profile.id)
        let destination = try owner(profile.id)
        let tab = try XCTUnwrap(source.browser.activeTab)
        source.browser.open(URL(string: "data:text/html,<title>Fields</title><input id='field'>")!)
        try await waitUntil { tab.pageTitle == "Fields" && !tab.isLoading }
        XCTAssertTrue(source.browser.moveTab(tab.id, to: destination.browser))
        tab.hasPasswordFields = false
        _ = try await tab.webView?.evaluateJavaScript("document.body.appendChild(document.createElement('input')).type='password'")
        try await waitUntil { tab.hasPasswordFields }
        XCTAssertTrue(tab.browser === destination.browser)
    }

    func testDetachedTabRetainsProfileAndSessionWithoutRestoringAnUnrelatedWindow() throws {
        let profile = try profiles.create(name: "Detach")
        let otherProfile = try profiles.create(name: "Other")
        let source = try owner(profile.id)
        let other = try owner(otherProfile.id)
        let tab = try XCTUnwrap(source.browser.activeTab)
        let view = tab.webView
        XCTAssertFalse(source.browser.moveTab(tab.id, to: other.browser))
        let token = try XCTUnwrap(TabWindowTransfer.prepare(tabID: tab.id, source: source.browser, at: .zero))
        XCTAssertNil(TabWindowTransfer.take(token, profileID: otherProfile.id, isPrivate: false))
        let destination = try ProfileWindowController(profiles: profiles, profileID: profile.id, tabTransferID: token)
        owners.append(destination)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: true)
        defer { window.orderOut(nil) }
        destination.connect(window)
        XCTAssertTrue(destination.browser.activeTab === tab)
        XCTAssertTrue(tab.webView === view)
        XCTAssertEqual(destination.browser.profileID, profile.id)
        XCTAssertEqual(destination.browser.websiteDataStore.identifier, profile.id)
        XCTAssertEqual(destination.additionalWindows, 0)
        XCTAssertEqual(destination.browser.tabs.count, 1)
        XCTAssertNil(source.browser.tab(withID: tab.id))
        XCTAssertFalse(source.browser.canReopenClosedTab)
        XCTAssertEqual(profiles.context(for: profile.id)?.session.snapshot.windows.count, 1)
        XCTAssertTrue(source.isClosed)
        XCTAssertTrue(profiles.context(for: profile.id)?.session.snapshot.closedWindows.isEmpty == true)
        source.close()
        XCTAssertTrue(tab.webView === view)
        XCTAssertTrue(tab.browser === destination.browser)
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

    func testProfileRoundTripRetainsSplitWithoutSharingPagesOrCookies() async throws {
        let a = try profiles.create(name: "Split A")
        let b = try profiles.create(name: "Split B")
        let window = try owner(a.id)
        let original = window.browser
        original.startSplitView()
        let ids = original.splitTabIDs
        let views = original.splitTabs.compactMap(\.webView)
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "split.example", .path: "/", .name: "split", .value: "a"]))
        await original.websiteDataStore.httpCookieStore.setCookie(cookie)
        window.switchTo(b.id)
        XCTAssertFalse(window.browser.isSplitView)
        window.browser.startSplitView()
        XCTAssertFalse(window.browser.splitTabIDs.contains { ids.contains($0) })
        let cookies = await window.browser.websiteDataStore.httpCookieStore.allCookies()
        XCTAssertFalse(cookies.contains { $0.name == "split" })
        window.switchTo(a.id)
        XCTAssertTrue(window.browser === original)
        XCTAssertEqual(original.splitTabIDs, ids)
        XCTAssertEqual(original.splitTabs.compactMap(\.webView), views)
        XCTAssertTrue(original.splitTabs.allSatisfy { $0.webView?.configuration.websiteDataStore.identifier == a.id })
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

    func testProfileRoundTripRestoresNativeWindowThemeWithoutOpeningSettings() throws {
        let pro = try profiles.create(name: "Pro")
        let perso = try profiles.create(name: "Perso")
        let first = try owner(pro.id)
        first.browser.appearance.selection = .light
        try XCTUnwrap(profiles.context(for: perso.id)).preferences.appearance.selection = .dark
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        let material = NSVisualEffectView()
        window.contentView = material
        first.connect(window)

        for _ in 0..<3 {
            XCTAssertEqual(window.appearance?.name, .aqua)
            XCTAssertEqual(material.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)
            first.switchBy(1)
            XCTAssertEqual(first.browser.profileID, perso.id)
            XCTAssertEqual(window.appearance?.name, .darkAqua)
            XCTAssertEqual(material.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
            first.switchBy(-1)
            XCTAssertEqual(first.browser.profileID, pro.id)
        }
        XCTAssertEqual(window.appearance?.name, .aqua)
    }

    func testThemeChangesOnlyUpdateWindowsCurrentlyShowingThatProfile() throws {
        let pro = try profiles.create(name: "Pro")
        let perso = try profiles.create(name: "Perso")
        let first = try owner(pro.id)
        let second = try owner(pro.id)
        let proAppearance = first.browser.appearance
        let persoAppearance = try XCTUnwrap(profiles.context(for: perso.id)).preferences.appearance
        proAppearance.selection = .light
        persoAppearance.selection = .dark
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        let otherWindow = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        first.connect(window)
        second.connect(otherWindow)
        first.switchTo(perso.id)

        proAppearance.selection = .dark
        XCTAssertEqual(otherWindow.appearance?.name, .darkAqua)
        proAppearance.selection = .light
        XCTAssertEqual(otherWindow.appearance?.name, .aqua)
        XCTAssertEqual(window.appearance?.name, .darkAqua, "A parked profile must not recolor this window")
        persoAppearance.selection = .system
        XCTAssertNil(window.appearance, "System must clear the explicit native appearance")
        XCTAssertEqual(otherWindow.appearance?.name, .aqua)
        first.switchTo(pro.id)
        XCTAssertEqual(window.appearance?.name, .aqua)
        first.switchTo(perso.id)
        XCTAssertNil(window.appearance)

        first.connect(nil)
        persoAppearance.selection = .dark
        XCTAssertNil(window.appearance, "A detached window must no longer follow this profile")
        second.close()
        proAppearance.selection = .dark
        XCTAssertEqual(otherWindow.appearance?.name, .aqua, "A closed owner must detach its window")
    }

    func testPrivateWindowRemainsDarkWhenRegularProfileThemeChanges() throws {
        let pro = try profiles.create(name: "Pro")
        let regular = try owner(pro.id)
        let privateOwner = try owner(pro.id, privateMode: true)
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        privateOwner.connect(window)
        XCTAssertEqual(window.appearance?.name, .darkAqua)
        regular.browser.appearance.selection = .light
        privateOwner.switchTo(pro.id)
        XCTAssertEqual(window.appearance?.name, .darkAqua)
    }

    func testSystemProfileReturnsToSystemThemeAfterDarkProfileAndTracksAppearanceChanges() async throws {
        let original = NSApp.appearance
        defer { NSApp.appearance = original }
        NSApp.appearance = NSAppearance(named: .aqua)
        let pro = try profiles.create(name: "Pro")
        let perso = try profiles.create(name: "Perso")
        let first = try owner(pro.id)
        let proAppearance = first.browser.appearance
        proAppearance.selection = .system
        proAppearance.pageSelection = .light
        let persoAppearance = try XCTUnwrap(profiles.context(for: perso.id)).preferences.appearance
        persoAppearance.selection = .dark
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        first.connect(window)

        for _ in 0..<3 {
            first.switchTo(perso.id)
            XCTAssertEqual(first.browser.appearance.colorScheme, .dark)
            first.switchTo(pro.id)
            XCTAssertEqual(first.browser.appearance.colorScheme, .light)
            XCTAssertNil(window.appearance)
            XCTAssertEqual(proAppearance.pageSelection, .light)
        }
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try await waitUntil { proAppearance.colorScheme == .dark }
        XCTAssertEqual(proAppearance.selection, .system)
        XCTAssertEqual(proAppearance.pageSelection, .light)
        NSApp.appearance = NSAppearance(named: .aqua)
        try await waitUntil { proAppearance.colorScheme == .light }
        XCTAssertEqual(persoAppearance.colorScheme, .dark)
    }

    func testPrivateWindowIsIndependentAndCannotSwitchProfiles() throws {
        let a = try profiles.create(name: "A")
        let b = try profiles.create(name: "B")
        let first = try owner(a.id, privateMode: true)
        let original = first.browser
        first.switchTo(b.id)
        XCTAssertTrue(first.browser.isPrivate)
        XCTAssertNil(first.browser.history)
        XCTAssertNil(first.browser.passwords)
        XCTAssertTrue(first.browser === original)
        XCTAssertNil(first.browser.profileID)
        XCTAssertEqual(first.browser.appearance.selection, .dark)
        XCTAssertTrue(first.privateBookmarks.bookmarks.isEmpty)
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
    func testSessionDiscoveryDoesNotInitializeUnusedProfileResources() throws {
        let a = try profiles.create(name: "Lazy A")
        let b = try profiles.create(name: "Lazy B")
        let file = StoreFile(url: try XCTUnwrap(profiles.directory(for: b)).appending(path: "Session.plist"))
        file.writeNow(try PropertyListEncoder.binary.encode(SessionSnapshot(windows: [
            WindowSession(tabs: [TabSession(url: nil, title: "", interactionState: nil)], selectedIndex: 0)
        ])))
        var openedStores = [UUID]()
        let restarted = ProfileStore(root: root, defaults: defaults, dataStoreFactory: { profile in
            openedStores.append(profile.id)
            return .nonPersistent()
        })
        XCTAssertEqual(restarted.defaultWindowProfileID, b.id)
        XCTAssertTrue(openedStores.isEmpty)
        let discovered = try XCTUnwrap(restarted.session(for: b.id))
        XCTAssertTrue(discovered.hasPendingWindows)
        let context = try XCTUnwrap(restarted.context(for: b.id))
        XCTAssertTrue(context.session === discovered)
        XCTAssertEqual(openedStores, [b.id])
        restarted.session(for: a.id)?.closeParkedWindow(ownerID: UUID())
        XCTAssertEqual(openedStores, [b.id])
        context.prepareForDeletion()
    }

}
