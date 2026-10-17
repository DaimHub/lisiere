import AppKit
import SwiftUI
import XCTest
@testable import Browser

@MainActor
final class ToolbarLayoutTests: XCTestCase {
    private var customizableToolbar: BrowserToolbarLayout {
        BrowserToolbarLayout(entries: BrowserToolbarLayout.standard.entries.dropLast()
                             + [ToolbarEntry(.history), ToolbarEntry(.allActions)])
    }

    func testNewTabMovesOutOfStoredToolbarWithoutLosingOtherActions() {
        let saved = Data(#"{"version":2,"entries":[{"id":"group.nav","items":["back","newTab","reload"]},{"id":"newTab","items":["newTab"]},{"id":"address","items":["address"]},{"id":"home","items":["home"]}]}"#.utf8)
        var layout = BrowserToolbarLayout(data: saved)
        XCTAssertEqual(layout.items, [.profile, .back, .reload, .address, .home])
        XCTAssertEqual(layout.entry(containing: .back)?.id, "group.nav")
        XCTAssertEqual(layout.entry(containing: .back)?.items, [.back, .reload])
        XCTAssertFalse(layout.availableItems.contains(.newTab))
        XCTAssertFalse(BrowserToolbarLayout.standard.items.contains(.newTab))
        let migrated = layout
        layout.add(.newTab)
        XCTAssertEqual(layout, migrated)
        XCTAssertEqual(BrowserToolbarLayout(data: layout.storedValue), migrated)
        for width: CGFloat in [436, 1200] {
            let presentation = layout.presentation(width: width)
            XCTAssertFalse(presentation.visible.flatMap(\.items).contains(.newTab))
            XCTAssertFalse(presentation.overflow.contains(.newTab))
        }
    }

    func testLegacyMigrationPreservesCustomOrderAndSplitsNavigationIntoAGroup() {
        let layout = BrowserToolbarLayout(legacyValue: ["home", "profile", "navigation", "address", "newTab", "privateWindow"])
        XCTAssertEqual(layout.items, [.home, .profile, .back, .forward, .reload, .address, .privateWindow, .allActions])
        XCTAssertEqual(layout.entries[2].items, [.back, .forward, .reload])
        XCTAssertTrue(layout.entries[2].isGroup)
        XCTAssertEqual(BrowserToolbarLayout(data: layout.storedValue), layout)
    }

    func testInvalidPreferencesRecoverAUsableToolbarWithoutDuplicateActions() {
        for value in [nil, [], ["future-control"]] as [[String]?] {
            XCTAssertEqual(BrowserToolbarLayout(legacyValue: value), .standard)
        }
        XCTAssertEqual(BrowserToolbarLayout(data: Data("not JSON".utf8)), .standard)
        let saved = Data(#"{"version":2,"entries":[{"id":"group.a","items":["home","address","home","unknown"]},{"id":"group.a","items":["newTab","reload"]}]}"#.utf8)
        let repaired = BrowserToolbarLayout(data: saved)
        XCTAssertEqual(repaired.items, [.profile, .home, .address, .reload])
        XCTAssertEqual(Set(repaired.entries.map(\.id)).count, repaired.entries.count)
        XCTAssertFalse(repaired.items.contains(.allActions), "A V2 layout may intentionally hide All Actions")
    }

    func testProfileAndAddressCannotJoinGroupsButRemainMovable() {
        for id in ["profile", "address"] {
            var layout = customizableToolbar
            layout.group(id, with: "history")
            layout.group("history", with: id)
            layout.group(id, with: "group.navigation")
            XCTAssertFalse(layout.move(id, toGroup: "group.navigation", at: 0))
            XCTAssertEqual(layout, customizableToolbar)
            XCTAssertTrue(layout.move(id, toGroup: nil, at: layout.entries.count))
            XCTAssertEqual(layout.entries.last?.id, id)
        }
        var layout = customizableToolbar
        layout.group("allActions", with: "history")
        let group = layout.entry(containing: .history)!
        XCTAssertEqual(group.items, [.history, .allActions])
        layout.ungroup(group.id)
        XCTAssertEqual(layout.entries.suffix(2).map(\.items), [[.history], [.allActions]])
    }

    func testStoredGroupsSplitAroundProfileAndAddressWithoutChangingOrder() {
        let saved = Data(#"{"version":2,"entries":[{"id":"group.old","items":["back","forward","profile","reload","home","address","newTab","allActions"]}]}"#.utf8)
        let layout = BrowserToolbarLayout(data: saved)
        XCTAssertEqual(layout.items, [.back, .forward, .profile, .reload, .home, .address, .allActions])
        XCTAssertEqual(layout.entries.map(\.items), [[.back, .forward], [.profile], [.reload, .home], [.address], [.allActions]])
        XCTAssertEqual(layout.entries.first?.id, "group.old")
        XCTAssertEqual(Set(layout.entries.map(\.id)).count, layout.entries.count)
        XCTAssertEqual(BrowserToolbarLayout(data: layout.storedValue), layout)
    }

    func testPreviewMovesGroupsAndButtonsLeftAndRightWithoutCrossingBoundaries() {
        var layout = customizableToolbar
        layout.move("group.navigation", by: -1)
        XCTAssertEqual(layout.entries.first?.id, "group.navigation")
        layout.move("group.navigation", by: -1)
        XCTAssertEqual(layout.entries.first?.id, "group.navigation")
        layout.move("group.navigation", by: 1)
        XCTAssertEqual(layout, customizableToolbar)

        layout.move("back", by: -1)
        XCTAssertEqual(layout, customizableToolbar)
        layout.move("back", by: 1)
        XCTAssertEqual(layout.entry(containing: .back)?.items, [.forward, .back, .reload])
        layout.move("back", by: 1)
        let atRightEdge = layout
        layout.move("back", by: 1)
        XCTAssertEqual(layout, atRightEdge)
        layout.move("back", by: -1)
        layout.move("back", by: -1)
        layout.move("allActions", by: 1)
        layout.move("missing", by: 1)
        XCTAssertEqual(layout, customizableToolbar)
        XCTAssertEqual(BrowserToolbarLayout(data: atRightEdge.storedValue), atRightEdge)
    }

    func testNavigationCanBeSeparatedAndRegroupedWithOtherActions() {
        var layout = customizableToolbar
        layout.ungroup("group.navigation")
        XCTAssertTrue(layout.entries.prefix(4).allSatisfy { !$0.isGroup })
        layout.add(.home)
        layout.group("home", with: "reload")
        XCTAssertEqual(layout.entry(containing: .reload)?.items, [.reload, .home])
        layout.separate(.reload)
        XCTAssertEqual(layout.entry(containing: .home)?.items, [.home])
        XCTAssertEqual(layout.entry(containing: .reload)?.items, [.reload])
    }

    func testMoveIndicesReorderEntriesInBothDirectionsAndToEnd() {
        var layout = customizableToolbar
        XCTAssertTrue(layout.move("profile", toGroup: nil, at: layout.entries.count))
        XCTAssertEqual(layout.entries.last?.id, "profile")
        XCTAssertTrue(layout.move("profile", toGroup: nil, at: 0))
        XCTAssertEqual(layout, customizableToolbar)
        layout.move("group.navigation", by: 1)
        XCTAssertEqual(layout.entries.map(\.id), ["profile", "address", "group.navigation", "history", "allActions"])
        layout.move("group.navigation", by: -1)
        XCTAssertEqual(layout, customizableToolbar)
        layout.move("profile", by: -1)
        XCTAssertEqual(layout, customizableToolbar)
    }

    func testMoveIndicesReorderChildrenAndMoveButtonsInAndOutOfGroups() {
        var layout = customizableToolbar
        XCTAssertTrue(layout.move("back", toGroup: "group.navigation", at: 3))
        XCTAssertEqual(layout.entry(containing: .back)?.items, [.forward, .reload, .back])
        layout.move("back", by: -1)
        XCTAssertEqual(layout.entry(containing: .back)?.items, [.forward, .back, .reload])
        XCTAssertTrue(layout.move("history", toGroup: "group.navigation", at: 1))
        XCTAssertEqual(layout.entry(containing: .back)?.items, [.forward, .history, .back, .reload])
        XCTAssertTrue(layout.move("reload", toGroup: nil, at: 0))
        XCTAssertEqual(layout.entries.first?.items, [.reload])
        XCTAssertEqual(layout.entry(containing: .back)?.items, [.forward, .history, .back])
        XCTAssertEqual(Set(layout.items).count, layout.items.count)
    }

    func testMovingBetweenGroupsCollapsesSingletonsAndMergesWholeGroups() {
        var layout = customizableToolbar
        layout.add(.home)
        layout.group("home", with: "history")
        let group = layout.entry(containing: .home)!.id
        XCTAssertTrue(layout.move("home", toGroup: "group.navigation", at: 0))
        XCTAssertEqual(layout.entry(containing: .history)?.id, "history")
        XCTAssertFalse(layout.entries.contains { $0.id == group })
        layout.group("allActions", with: "history")
        let other = layout.entry(containing: .history)!.id
        XCTAssertTrue(layout.move(other, toGroup: "group.navigation", at: 2))
        XCTAssertEqual(layout.entry(containing: .back)?.items, [.home, .back, .history, .allActions, .forward, .reload])
        XCTAssertFalse(layout.entries.contains { $0.id == other })
    }

    func testInvalidMovesAndSelfGroupingNeverLoseControls() {
        var layout = customizableToolbar
        XCTAssertFalse(layout.move("unknown", toGroup: nil, at: 0))
        XCTAssertFalse(layout.move("profile", toGroup: "unknown", at: 0))
        XCTAssertFalse(layout.move("group.navigation", toGroup: "group.navigation", at: 0))
        layout.group("back", with: "group.navigation")
        layout.group("address", with: "address")
        layout.group("unknown", with: "profile")
        XCTAssertEqual(layout, customizableToolbar)
        layout.remove(.profile)
        layout.remove(.address)
        XCTAssertEqual(layout, customizableToolbar)
        layout.remove(.forward)
        layout.remove(.reload)
        XCTAssertEqual(layout.entry(containing: .back)?.id, "back")
        layout.add(.home)
        layout.add(.home)
        XCTAssertEqual(layout.items.filter { $0 == .home }.count, 1)
    }

    func testToolbarPersistsPerProfileAndCopiesGroupsIndependently() throws {
        let name = "ToolbarTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let root = FileManager.default.temporaryDirectory.appending(path: name)
        defaults.set(["home", "navigation", "profile", "address", "history"], forKey: BrowserToolbarLayout.legacyStorageKey)
        let store = ProfileStore(root: root, defaults: defaults)
        defer {
            for profile in store.profiles where !profile.isInitial {
                defaults.removePersistentDomain(forName: ProfileStore.defaultsDomain(for: profile.id))
            }
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: root)
        }
        let first = try XCTUnwrap(store.context(for: BrowserProfile.initialID)).preferences
        XCTAssertEqual(first.toolbarLayout.items.first, .home)
        first.toolbarLayout.group("home", with: "history")
        XCTAssertEqual(ProfilePreferences(defaults: defaults).toolbarLayout, first.toolbarLayout)
        XCTAssertEqual(defaults.stringArray(forKey: BrowserToolbarLayout.legacyStorageKey), ["home", "navigation", "profile", "address", "history"])
        let second = try store.create(name: "Work")
        XCTAssertEqual(try XCTUnwrap(store.context(for: second.id)).preferences.toolbarLayout, .standard)
        let copy = try store.create(name: "Copy", copying: BrowserProfile.initialID)
        let copied = try XCTUnwrap(store.context(for: copy.id)).preferences
        XCTAssertEqual(copied.toolbarLayout, first.toolbarLayout)
        copied.toolbarLayout.remove(.home)
        XCTAssertTrue(first.toolbarLayout.items.contains(.home))
        first.toolbarLayout = .standard
        XCTAssertEqual(ProfilePreferences(defaults: defaults).toolbarLayout, .standard)
        XCTAssertEqual(ProfilePreferences().toolbarLayout, .standard)
    }

    func testNarrowToolbarPreservesSavedGroupsAndActionOrder() {
        var layout = customizableToolbar
        for item in layout.availableItems { layout.add(item) }
        layout.group("home", with: "group.navigation")
        let original = layout
        let narrow = layout.presentation(width: 436)
        XCTAssertTrue(narrow.compactProfile)
        let visible = narrow.visible.flatMap(\.items)
        for item in [BrowserToolbarItem.address, .back, .forward, .reload, .allActions] {
            XCTAssertTrue(visible.contains(item))
        }
        XCTAssertFalse(narrow.overflow.isEmpty)
        XCTAssertTrue(narrow.overflow.allSatisfy(\.canOverflow))
        XCTAssertEqual(narrow.overflow, layout.items.filter { !visible.contains($0) })
        XCTAssertEqual(layout, original)
        let wide = layout.presentation(width: 1200)
        XCTAssertFalse(wide.compactProfile)
        XCTAssertEqual(wide.visible, layout.entries)
        XCTAssertTrue(wide.overflow.isEmpty)
    }

    func testDownloadsAppearOnDemandWithoutDuplicatingGroupedButton() {
        var layout = customizableToolbar
        XCTAssertFalse(layout.presentation(width: 900).visible.flatMap(\.items).contains(.downloads))
        XCTAssertEqual(layout.presentation(width: 900, hasDownloads: true).visible.last?.items, [.downloads])
        layout.add(.downloads)
        layout.group("downloads", with: "history")
        XCTAssertEqual(layout.presentation(width: 900, hasDownloads: true).visible.flatMap(\.items).filter { $0 == .downloads }.count, 1)
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
