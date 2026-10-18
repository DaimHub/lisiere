import WebKit
import XCTest
@testable import Browser

@MainActor
final class TabOrganizationTests: XCTestCase {
    func testDropReordersPinsInBothDirectionsWithoutLoadingOrChangingSelection() throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        browser.restoreSession(WindowSession(tabs: (0..<5).map {
            TabSession(url: URL(string: "https://example.com/\($0)"), title: "Pin \($0)", interactionState: nil, isPinned: true)
        } + [TabSession(url: nil, title: "", interactionState: nil)], selectedIndex: 5))
        let ids = browser.tabs.map(\.id)
        let active = browser.activeTabID
        browser.dropTab(ids[4], beside: ids[0], after: false)
        XCTAssertEqual(browser.tabs.map(\.id), [ids[4], ids[0], ids[1], ids[2], ids[3], ids[5]])
        browser.dropTab(ids[0], beside: ids[3], after: true)
        XCTAssertEqual(browser.tabs.map(\.id), [ids[4], ids[1], ids[2], ids[3], ids[0], ids[5]])
        XCTAssertEqual(browser.activeTabID, active)
        XCTAssertTrue(browser.tabs.prefix(5).allSatisfy { $0.isPinned && $0.isSuspended && $0.webView == nil })
        let before = browser.tabs.map(\.id)
        browser.dropTab(ids[0], beside: ids[5], after: true)
        browser.dropTab(UUID(), beside: ids[3], after: false)
        XCTAssertEqual(browser.tabs.map(\.id), before)
    }

    func testDropOntoAnotherGroupsTabChangesMembershipAndExactPosition() {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        for _ in 0..<3 { browser.addTab() }
        let tabs = browser.tabs
        let views = tabs.map(\.webView)
        let first = browser.createGroup(name: "First", color: .blue, tabID: tabs[0].id)
        let second = browser.createGroup(name: "Second", color: .green, tabID: tabs[1].id)
        browser.assignTab(tabs[2].id, to: second)
        browser.dropTab(tabs[0].id, beside: tabs[1].id, after: true)
        XCTAssertEqual(tabs[0].groupID, second)
        XCTAssertEqual(browser.tabs.map(\.id), [tabs[1].id, tabs[0].id, tabs[2].id, tabs[3].id])
        XCTAssertEqual(browser.tabSections.first?.group?.id, first)
        XCTAssertEqual(browser.tabSections.first?.tabCount, 0)
        browser.dropTab(tabs[0].id, beside: tabs[3].id, after: false)
        XCTAssertNil(tabs[0].groupID)
        XCTAssertEqual(tabs.map(\.webView), views)
    }

    func testDropIntoCollapsedEmptyGroupAndOutPreservesPinsAndSplitPair() throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        browser.startSplitView()
        let pair = browser.tabs
        pair.forEach { browser.setPinned(true, for: $0.id) }
        let group = browser.createGroup(name: "Empty", color: .purple)
        browser.toggleGroupCollapsed(group)
        browser.dropTab(pair[0].id, into: group)
        XCTAssertTrue(pair.allSatisfy { $0.groupID == group && $0.isPinned })
        XCTAssertFalse(browser.groups[0].isCollapsed)
        XCTAssertEqual(browser.splitTabIDs, pair.map(\.id))
        XCTAssertEqual(browser.tabStripGroups.count, 1)
        browser.dropTab(pair[0].id, into: nil)
        XCTAssertTrue(pair.allSatisfy { $0.groupID == nil && $0.isPinned })
        browser.dropTab(pair[0].id, into: UUID())
        XCTAssertTrue(pair.allSatisfy { $0.groupID == nil })
    }

    func testPinsLeadAndSurviveEveryTabClosurePath() throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        for _ in 0..<3 { browser.addTab() }
        let ids = browser.tabs.map(\.id)
        browser.setPinned(true, for: ids[2])
        XCTAssertEqual(browser.tabs.map(\.id), [ids[2], ids[0], ids[1], ids[3]])
        browser.activeTabID = ids[2]
        browser.closeActiveTab()
        browser.closeTab(ids[2])
        browser.tab(withID: ids[2])?.requestCloseFromPage()
        XCTAssertEqual(browser.tabs.count, 4)
        XCTAssertFalse(browser.canReopenClosedTab)
        browser.closeOtherTabs(than: ids[0])
        XCTAssertEqual(browser.tabs.map(\.id), [ids[2], ids[0]])
        browser.closeTabs(after: ids[2])
        XCTAssertEqual(browser.tabs.map(\.id), [ids[2]])
        browser.addTab()
        browser.closeTabs(afterGroupContaining: ids[2])
        XCTAssertEqual(browser.tabs.map(\.id), [ids[2]])
        browser.setPinned(false, for: ids[2])
        browser.closeTab(ids[2])
        XCTAssertNotEqual(browser.activeTabID, ids[2])
        XCTAssertEqual(browser.tabs.count, 1)
    }

    func testFolderInsertionPreservesMixedPinsSplitPagesMetadataAndSessionOrder() throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        for _ in 0..<5 { browser.addTab() }
        let tabs = browser.tabs
        let views = tabs.map(\.webView)
        let first = browser.createGroup(name: "First", color: .purple, tabID: tabs[0].id)
        let second = browser.createGroup(name: "Second", color: .green, tabID: tabs[1].id)
        let empty = browser.createGroup(name: "Empty", color: .orange)
        browser.assignTab(tabs[2].id, to: first)
        browser.assignTab(tabs[3].id, to: first)
        browser.assignTab(tabs[4].id, to: second)
        browser.setPinned(true, for: tabs[0].id)
        browser.setPinned(true, for: tabs[1].id)
        browser.activeTabID = tabs[2].id
        browser.startSplitView(with: tabs[3].id)
        browser.toggleGroupCollapsed(first)
        let active = browser.activeTabID
        let split = browser.splitTabIDs
        let metadata = Dictionary(uniqueKeysWithValues: browser.groups.map { ($0.id, $0) })
        let memberships = tabs.map(\.groupID)
        browser.moveGroup(first, beside: empty, after: true)
        XCTAssertEqual(browser.groups.map(\.id), [second, empty, first])
        XCTAssertEqual(browser.tabs.map(\.id), [tabs[1].id, tabs[0].id, tabs[4].id, tabs[2].id, tabs[3].id, tabs[5].id])
        XCTAssertEqual(browser.tabSections.filter(\.isPinned).compactMap { $0.group?.id }, [second, first])
        XCTAssertEqual(browser.tabSections.filter { !$0.isPinned }.compactMap { $0.group?.id }, [second, empty, first])
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: browser.groups.map { ($0.id, $0) }), metadata)
        XCTAssertEqual(tabs.map(\.groupID), memberships)
        XCTAssertEqual(tabs.map(\.webView), views)
        XCTAssertEqual(browser.activeTabID, active)
        XCTAssertEqual(browser.splitTabIDs, split)
        XCTAssertTrue(browser.isSplitView)
        let session = browser.windowSession()
        let restored = try PropertyListDecoder().decode(WindowSession.self, from: PropertyListEncoder().encode(session))
        XCTAssertEqual(restored.groups, browser.groups)
        XCTAssertEqual(restored.tabs.map(\.groupID), browser.tabs.map(\.groupID))
        browser.moveGroup(first, beside: second, after: false)
        XCTAssertEqual(browser.groups.map(\.id), [first, second, empty])
        browser.moveGroup(first, beside: first, after: true)
        browser.moveGroup(UUID(), beside: second, after: true)
        browser.moveGroup(first, beside: UUID(), after: true)
        XCTAssertEqual(browser.groups.map(\.id), [first, second, empty])
    }

    func testGroupsPartitionPinsWithoutReplacingViewsOrSelection() throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        for _ in 0..<3 { browser.addTab() }
        let tabs = browser.tabs
        let views = tabs.map(\.webView)
        let active = browser.activeTabID
        let first = browser.createGroup(name: "  Work  ", color: .green, tabID: tabs[2].id)
        let second = browser.createGroup(name: "Read", color: .purple, tabID: tabs[0].id)
        browser.assignTab(tabs[3].id, to: first)
        browser.setPinned(true, for: tabs[3].id)
        browser.setPinned(true, for: tabs[1].id)
        XCTAssertEqual(browser.tabs.map(\.id), [tabs[1].id, tabs[3].id, tabs[2].id, tabs[0].id])
        XCTAssertEqual(browser.groups.map(\.name), ["Work", "Read"])
        XCTAssertEqual(browser.tabSections.map(\.tabCount), [1, 1, 1, 1])
        XCTAssertEqual(browser.activeTabID, active)
        XCTAssertEqual(tabs.map(\.webView), views)
        browser.updateGroup(first, name: "Research", color: .orange)
        XCTAssertEqual(browser.groups[0].color, .orange)
        browser.moveGroup(second, by: -1)
        XCTAssertEqual(browser.tabs.map(\.id), [tabs[1].id, tabs[3].id, tabs[0].id, tabs[2].id])
        browser.ungroup(first)
        XCTAssertEqual(browser.tabs.count, 4)
        XCTAssertTrue(tabs[3].isPinned)
        XCTAssertNil(tabs[2].groupID)
        XCTAssertEqual(tabs.map(\.webView), views)
        XCTAssertEqual(browser.activeTabID, active)
    }

    func testPinningDuringDeferredPopupClosureKeepsPendingNavigationAlive() async throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        let tab = try XCTUnwrap(browser.activeTab)
        let token = tab.beginPasswordPrompt()
        tab.requestCloseFromPage()
        let navigation = Task { await tab.waitForPasswordDecision() }
        await Task.yield()
        browser.setPinned(true, for: tab.id)
        tab.finishPasswordPrompt(token)
        let canContinue = await navigation.value
        XCTAssertTrue(canContinue)
        XCTAssertTrue(browser.activeTab === tab)
    }

    func testCollapsedGroupsRevealKeyboardSelectionAndKeepEmptyFolders() throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        let first = try XCTUnwrap(browser.activeTabID)
        let group = browser.createGroup(name: "Work", color: .blue, tabID: first)
        browser.addTab()
        browser.toggleGroupCollapsed(group)
        XCTAssertTrue(browser.tabSections.first?.visibleCards.isEmpty == true)
        browser.selectTab(at: 0)
        XCTAssertEqual(browser.activeTabID, first)
        XCTAssertFalse(browser.groups[0].isCollapsed)
        browser.closeTab(first)
        XCTAssertEqual(browser.groups.count, 1)
        XCTAssertEqual(browser.tabSections.first?.tabCount, 0)
        browser.addTab(in: group)
        XCTAssertEqual(browser.activeTab?.groupID, group)
        browser.assignTab(try XCTUnwrap(browser.activeTabID), to: UUID())
        XCTAssertEqual(browser.activeTab?.groupID, group)
    }

    func testReorderingCannotDragTabsAcrossPinOrFolderBoundaries() throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        for _ in 0..<3 { browser.addTab() }
        let ids = browser.tabs.map(\.id)
        browser.setPinned(true, for: ids[0])
        browser.createGroup(name: "Group", color: .red, tabID: ids[1])
        let before = browser.tabs.map(\.id)
        browser.moveTab(ids[0], to: 3)
        browser.moveTabGroup(containing: ids[1], beside: ids[3])
        XCTAssertEqual(browser.tabs.map(\.id), before)
        browser.moveTabGroup(containing: ids[2], beside: ids[3])
        XCTAssertEqual(browser.tabs.map(\.id), [ids[0], ids[1], ids[3], ids[2]])
    }

    func testSplitAcrossOrganizationBoundariesKeepsPinAndGroupLocations() throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        let first = try XCTUnwrap(browser.activeTabID)
        browser.startSplitView()
        let second = try XCTUnwrap(browser.activeTabID)
        browser.setPinned(true, for: second)
        XCTAssertTrue(browser.isSplitView)
        XCTAssertEqual(browser.tabStripGroups.map { $0.tabs.count }, [1, 1])
        browser.closeOtherTabs(than: first)
        XCTAssertEqual(browser.tabs.count, 2)
        browser.closeTabs(afterGroupContaining: second)
        XCTAssertEqual(browser.tabs.map(\.id), [second])
        XCTAssertFalse(browser.isSplitView)
        XCTAssertEqual(browser.activeTabID, second)
    }

    func testDuplicateAndChildOfPinAreUnpinnedButKeepGroup() throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        let pin = try XCTUnwrap(browser.activeTab)
        let group = browser.createGroup(name: "Work", color: .blue, tabID: pin.id)
        browser.setPinned(true, for: pin.id)
        browser.duplicateTab(pin.id)
        let duplicate = try XCTUnwrap(browser.activeTab)
        XCTAssertFalse(duplicate.isPinned)
        XCTAssertEqual(duplicate.groupID, group)
        let child = browser.openChildTab(of: pin, select: false)
        XCTAssertFalse(child.isPinned)
        XCTAssertEqual(child.groupID, group)
        XCTAssertEqual(browser.tabs.first?.id, pin.id)
        browser.closeTab(duplicate.id)
        browser.reopenClosedTab()
        XCTAssertEqual(browser.activeTab?.groupID, group)
    }

    func testSessionRoundTripKeepsPinsGroupsCollapseAndLazyLoading() throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        let savedGroup = TabGroup(name: "Work", color: .purple, isCollapsed: true)
        let snapshot = WindowSession(tabs: [
            TabSession(url: URL(string: "https://example.com"), title: "Pinned", interactionState: nil,
                       isPinned: true, groupID: savedGroup.id),
            TabSession(url: nil, title: "", interactionState: nil)
        ], selectedIndex: 1, groups: [savedGroup])
        let data = try PropertyListEncoder.binary.encode(snapshot)
        browser.restoreSession(try PropertyListDecoder().decode(WindowSession.self, from: data))
        XCTAssertEqual(browser.groups, [savedGroup])
        XCTAssertTrue(browser.tabs[0].isPinned)
        XCTAssertTrue(browser.tabs[0].isSuspended)
        XCTAssertEqual(browser.windowSession(), snapshot)
        let normal = BrowserModel.makePrivate()
        defer { normal.releaseClosedWindow() }
        let store = SessionStore(file: nil)
        _ = store.attach(browser)
        XCTAssertTrue(store.snapshot.windows.isEmpty)
        XCTAssertTrue(normal.groups.isEmpty)
        XCTAssertFalse(normal.tabs[0].isPinned)
    }

    func testLegacySessionsAndOrphanedMembershipRemainReadable() throws {
        let legacy: [String: Any] = ["tabs": [["title": "Old", "url": ["relative": "https://example.com"]]], "selectedIndex": 0]
        let bytes = try PropertyListSerialization.data(fromPropertyList: legacy, format: .binary, options: 0)
        let saved = try PropertyListDecoder().decode(WindowSession.self, from: bytes)
        XCTAssertFalse(saved.tabs[0].isPinned)
        XCTAssertTrue(saved.groups.isEmpty)
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        let group = TabGroup(name: "Valid")
        browser.restoreSession(WindowSession(tabs: [TabSession(url: nil, title: "", interactionState: nil, groupID: UUID())],
                                             selectedIndex: 99, groups: [group, group]))
        XCTAssertNil(browser.tabs[0].groupID)
        XCTAssertEqual(browser.groups.count, 1)
        XCTAssertEqual(browser.activeTabID, browser.tabs[0].id)
    }

    func testPinnedPageCanSuspendAndRestoreItsHistory() async throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        let first = URL(string: "data:text/html,<title>First</title>")!
        let second = URL(string: "data:text/html,<title>Second</title>")!
        browser.open(first)
        let tab = try XCTUnwrap(browser.activeTab)
        try await waitUntil { tab.pageTitle == "First" && !tab.isLoading }
        browser.open(second)
        try await waitUntil { tab.pageTitle == "Second" && !tab.isLoading && tab.canGoBack }
        browser.setPinned(true, for: tab.id)
        browser.addTab()
        XCTAssertTrue(browser.suspendableTabs.contains { $0 === tab })
        await browser.suspendTabs([tab])
        XCTAssertTrue(tab.isSuspended)
        XCTAssertTrue(tab.isPinned)
        browser.activeTabID = tab.id
        try await waitUntil { tab.pageTitle == "Second" && !tab.isLoading && tab.canGoBack }
        XCTAssertEqual(tab.backList.map(\.url), [first])
        XCTAssertFalse(tab.isSuspended)
    }

    func testSessionAutosaveTracksOnlyMetadataChanges() async throws {
        let file = StoreFile(url: FileManager.default.temporaryDirectory.appending(path: "Pins-\(UUID()).plist"))
        let store = SessionStore(file: file)
        let browser = BrowserModel()
        defer { store.disableWrites(); browser.releaseClosedWindow(); try? FileManager.default.removeItem(at: file.url) }
        _ = store.attach(browser)
        let id = try XCTUnwrap(browser.activeTabID)
        let group = browser.createGroup(name: "Initial", color: .blue, tabID: id)
        browser.setPinned(true, for: id)
        func saved() -> WindowSession? {
            guard let bytes = file.readNow() else { return nil }
            return (try? PropertyListDecoder().decode(SessionSnapshot.self, from: bytes))?.windows.first
        }
        try await waitUntil { saved()?.tabs.first?.isPinned == true }
        browser.updateGroup(group, name: "Renamed", color: .green)
        browser.toggleGroupCollapsed(group)
        try await waitUntil { saved()?.groups.first?.name == "Renamed" && saved()?.groups.first?.isCollapsed == true }
        XCTAssertEqual(saved()?.groups.first?.color, .green)
        XCTAssertEqual(saved()?.tabs.first?.groupID, group)
    }
}
