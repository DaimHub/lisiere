import XCTest
@testable import Browser

@MainActor
final class BookmarkStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "io.github.daimhub.lisiere.tests.bookmarks"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testToggleAddsThenRemovesAPage() {
        let store = BookmarkStore(defaults: makeDefaults())
        let url = URL(string: "https://swift.org")!

        store.toggle(title: "Swift", url: url)
        XCTAssertTrue(store.isBookmarked(url))

        store.toggle(title: "Swift", url: url)
        XCTAssertFalse(store.isBookmarked(url))
    }

    func testBookmarksPersistAcrossStores() {
        let defaults = makeDefaults()
        let store = BookmarkStore(defaults: defaults)
        store.add(title: "Swift", url: URL(string: "https://swift.org")!)
        store.add(title: "", url: URL(string: "https://www.apple.com")!)
        store.rename(store.bookmarks[0].id, to: "  Swift.org  ")

        let reloaded = BookmarkStore(defaults: defaults)

        XCTAssertEqual(reloaded.bookmarks.map(\.displayTitle), ["Swift.org", "apple.com"])
    }

    func testMoveReordersBookmarks() {
        let store = BookmarkStore(defaults: makeDefaults())
        for site in ["a.com", "b.com", "c.com"] {
            store.add(title: site, url: URL(string: "https://\(site)")!)
        }

        store.move(store.bookmarks[0].id, to: 2)

        XCTAssertEqual(store.bookmarks.map(\.title), ["b.com", "c.com", "a.com"])
    }

    func testEmptyAndNullNamesPersistAsIconOnlyWithoutLosingBookmarks() throws {
        let defaults = makeDefaults()
        let store = BookmarkStore(defaults: defaults)
        let url = URL(string: "https://www.example.com")!
        store.add(title: "Example", url: url)
        let id = try XCTUnwrap(store.bookmarks.first?.id)
        store.rename(id, to: " \n ")
        let restored = BookmarkStore(defaults: defaults)
        XCTAssertEqual(restored.bookmarks.count, 1)
        XCTAssertEqual(restored.bookmarks[0].id, id)
        XCTAssertNil(restored.bookmarks[0].title)
        XCTAssertNil(restored.bookmarks[0].visibleTitle)
        XCTAssertEqual(restored.bookmarks[0].displayTitle, "example.com")
        XCTAssertEqual(restored.bookmarks[0].url, url)
        restored.rename(id, to: "Restored name")
        XCTAssertEqual(restored.bookmarks[0].visibleTitle, "Restored name")
    }

    func testLegacyEmptyMissingAndNullTitlesDecodeTogether() throws {
        let rows: [[String: Any]] = [
            ["id": UUID().uuidString, "url": "https://named.example", "title": "Named"],
            ["id": UUID().uuidString, "url": "https://empty.example", "title": ""],
            ["id": UUID().uuidString, "url": "https://null.example", "title": NSNull()],
            ["id": UUID().uuidString, "url": "https://missing.example"]
        ]
        let defaults = makeDefaults()
        defaults.set(try JSONSerialization.data(withJSONObject: rows), forKey: "bookmarks")
        let store = BookmarkStore(defaults: defaults)
        XCTAssertEqual(store.bookmarks.count, 4)
        XCTAssertEqual(store.bookmarks.map(\.visibleTitle), ["Named", nil, nil, nil])
        XCTAssertEqual(store.bookmarks.map(\.displayTitle), ["Named", "empty.example", "null.example", "missing.example"])
        store.add(title: nil, url: URL(string: "https://new.example")!)
        XCTAssertEqual(BookmarkStore(defaults: defaults).bookmarks.count, 5)
    }

    func testBookmarksBarVisibility() {
        XCTAssertTrue(BookmarksBarVisibility.always.isVisible(onNewTab: false))
        XCTAssertTrue(BookmarksBarVisibility.newTabOnly.isVisible(onNewTab: true))
        XCTAssertFalse(BookmarksBarVisibility.newTabOnly.isVisible(onNewTab: false))
        XCTAssertFalse(BookmarksBarVisibility.never.isVisible(onNewTab: true))
    }

    func testTabLayoutTogglesAndSizesTheWindowControlsRow() {
        XCTAssertEqual(TabLayout.horizontal.toggled, .vertical)
        XCTAssertEqual(TabLayout.vertical.toggled, .horizontal)
        XCTAssertEqual(BrowserChrome.titlebarHeight(for: .horizontal), BrowserChrome.tabRowHeight)
        XCTAssertEqual(BrowserChrome.titlebarHeight(for: .vertical), BrowserChrome.navigationBarHeight)
    }
}
