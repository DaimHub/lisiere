import XCTest
@testable import Browser

@MainActor
final class ToolbarLayoutTests: XCTestCase {
    func testOldAndInvalidPreferencesRecoverAUsableToolbar() {
        for value in [nil, [], ["future-control"]] as [[String]?] {
            XCTAssertEqual(BrowserToolbarLayout(storedValue: value), .standard)
        }
        let repaired = BrowserToolbarLayout(storedValue: ["home", "address", "home", "future-control"])
        XCTAssertEqual(repaired.items, [.profile, .home, .address])
    }

    func testCustomizationKeepsRequiredItemsAndNoDuplicates() {
        var layout = BrowserToolbarLayout.standard
        layout.add(.home)
        layout.add(.home)
        layout.move(.home, by: -1)
        XCTAssertEqual(layout.items, [.profile, .navigation, .address, .home, .newTab])
        layout.remove(.profile)
        layout.remove(.address)
        layout.remove(.navigation)
        layout.move(.profile, by: -1)
        layout.move(.newTab, by: 1)
        XCTAssertEqual(layout.items, [.profile, .address, .home, .newTab])
        XCTAssertTrue(layout.availableItems.contains(.navigation))
        XCTAssertFalse(layout.availableItems.contains(.home))
    }

    func testToolbarPersistsPerProfileAndCopiesIndependently() throws {
        let name = "ToolbarTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let root = FileManager.default.temporaryDirectory.appending(path: name)
        let store = ProfileStore(root: root, defaults: defaults)
        defer {
            for profile in store.profiles where !profile.isInitial {
                defaults.removePersistentDomain(forName: ProfileStore.defaultsDomain(for: profile.id))
            }
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: root)
        }
        let first = try XCTUnwrap(store.context(for: BrowserProfile.initialID)).preferences
        first.toolbarLayout = BrowserToolbarLayout(items: [.home, .address, .profile, .privateWindow, .newTab])
        XCTAssertEqual(ProfilePreferences(defaults: defaults).toolbarLayout, first.toolbarLayout)
        let second = try store.create(name: "Work")
        let work = try XCTUnwrap(store.context(for: second.id)).preferences
        XCTAssertEqual(work.toolbarLayout, .standard)
        let copy = try store.create(name: "Copy", copying: BrowserProfile.initialID)
        let copied = try XCTUnwrap(store.context(for: copy.id)).preferences
        XCTAssertEqual(copied.toolbarLayout, first.toolbarLayout)
        copied.toolbarLayout.remove(.home)
        XCTAssertTrue(first.toolbarLayout.items.contains(.home))
        first.toolbarLayout = .standard
        XCTAssertEqual(ProfilePreferences(defaults: defaults).toolbarLayout, .standard)
        XCTAssertEqual(ProfilePreferences().toolbarLayout, .standard)
    }

    func testNarrowToolbarKeepsAddressAndMovesExtrasIntoOverflowInOrder() {
        let layout = BrowserToolbarLayout(items: BrowserToolbarItem.allCases)
        let narrow = layout.presentation(width: 436)
        XCTAssertTrue(narrow.compactProfile)
        XCTAssertTrue(narrow.visible.contains(.address))
        XCTAssertTrue(narrow.visible.contains(.navigation))
        XCTAssertTrue(narrow.visible.contains(.newTab))
        XCTAssertFalse(narrow.overflow.isEmpty)
        XCTAssertTrue(narrow.overflow.allSatisfy(\.canOverflow))
        XCTAssertEqual(narrow.visible + narrow.overflow, layout.items)
        let wide = layout.presentation(width: 1200)
        XCTAssertFalse(wide.compactProfile)
        XCTAssertEqual(wide.visible, layout.items)
        XCTAssertTrue(wide.overflow.isEmpty)
    }

    func testDownloadsAppearOnDemandWithoutDuplicatingConfiguredButton() {
        let standard = BrowserToolbarLayout.standard
        XCTAssertFalse(standard.presentation(width: 900).visible.contains(.downloads))
        XCTAssertEqual(standard.presentation(width: 900, hasDownloads: true).visible.last, .downloads)
        var configured = standard
        configured.add(.downloads)
        XCTAssertEqual(configured.presentation(width: 900, hasDownloads: true).visible.filter { $0 == .downloads }.count, 1)
        XCTAssertEqual(standard.items, BrowserToolbarLayout.defaultItems)
    }

    func testHomeReusesAnEmptyTabAndPreservesOpenPages() async throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        browser.preferences.newTabPage = .blank
        let page = try XCTUnwrap(browser.activeTab)
        let url = URL(string: "data:text/html,<title>Keep this page</title>")!
        page.load(url)
        try await waitUntil { !page.isLoading && page.pageTitle == "Keep this page" }
        browser.goHome()
        let home = try XCTUnwrap(browser.activeTab)
        XCTAssertNotEqual(home.id, page.id)
        XCTAssertTrue(home.isNewTab)
        XCTAssertTrue(home.showsHomePage)
        XCTAssertEqual(page.url, url)
        XCTAssertEqual(browser.tabs.count, 2)
        browser.activeTabID = page.id
        browser.goHome()
        XCTAssertEqual(browser.activeTabID, home.id)
        XCTAssertEqual(browser.tabs.count, 2)
        XCTAssertEqual(browser.preferences.newTabPage, .blank)
    }
}
