import XCTest
import Observation
@testable import Browser

@MainActor
final class BrowserModelTests: XCTestCase {
    func testStripSelectionNotifiesOnlyAffectedTabsAndTracksSplitAndClosure() throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        let first = try XCTUnwrap(browser.activeTab)
        browser.addTab()
        let second = try XCTUnwrap(browser.activeTab)
        browser.addTab()
        let third = try XCTUnwrap(browser.activeTab)
        let changes = SelectionObservationCounter()
        withObservationTracking { _ = first.stripSelection } onChange: {
            MainActor.assumeIsolated { changes.count += 1 }
        }
        browser.activeTabID = second.id
        browser.activeTabID = third.id
        XCTAssertEqual(changes.count, 0, "An unrelated card must not observe a global selection change")
        XCTAssertEqual(first.stripSelection, .background)
        XCTAssertEqual(second.stripSelection, .background)
        XCTAssertEqual(third.stripSelection, .active)

        browser.startSplitView(with: first.id)
        XCTAssertEqual(first.stripSelection, .active)
        XCTAssertEqual(third.stripSelection, .splitPartner)
        XCTAssertEqual(changes.count, 1)
        browser.activeTabID = second.id
        XCTAssertEqual(first.stripSelection, .background)
        XCTAssertEqual(third.stripSelection, .background)
        browser.activeTabID = third.id
        XCTAssertEqual(first.stripSelection, .splitPartner)
        XCTAssertEqual(third.stripSelection, .active)

        let unchanged = SelectionObservationCounter()
        withObservationTracking { _ = third.stripSelection } onChange: {
            MainActor.assumeIsolated { unchanged.count += 1 }
        }
        browser.setPinned(true, for: third.id)
        XCTAssertEqual(unchanged.count, 0, "Reordering the active card must not republish its role")
        browser.closeTab(first.id)
        XCTAssertEqual(first.stripSelection, .background)
        XCTAssertEqual(third.stripSelection, .active)
        XCTAssertFalse(browser.isSplitView)
        browser.activeTabID = UUID()
        XCTAssertTrue(browser.tabs.allSatisfy { $0.stripSelection == .background })
    }

    func testOrganizingTabsDoesNotInvalidateUnchangedPageSelection() throws {
        for split in [false, true] {
            let browser = BrowserModel.makePrivate()
            defer { browser.releaseClosedWindow() }
            let source = try XCTUnwrap(browser.activeTab)
            browser.addTab()
            browser.addTab()
            if split { browser.startSplitView(with: browser.tabs[1].id) }
            let active = try XCTUnwrap(browser.activeTab)
            let panes = browser.splitTabs
            let group = browser.createGroup(name: "Target", color: .green)
            let changes = SelectionObservationCounter()
            withObservationTracking {
                _ = browser.activeTab?.isNewTab
                _ = browser.splitTabs.map(\.id)
            } onChange: { MainActor.assumeIsolated { changes.count += 1 } }

            browser.dropTab(source.id, into: group)
            browser.collapseGroup(group)
            browser.dropTab(source.id, into: nil)
            browser.setPinned(true, for: source.id)
            browser.dropTab(source.id, into: group)
            browser.dropTab(active.id, into: group)
            XCTAssertTrue(browser.activeTab === active)
            XCTAssertEqual(browser.splitTabs.map(\.id), panes.map(\.id))
            XCTAssertEqual(changes.count, 0, "Organizing tabs must not rebuild the unchanged page and toolbar")

            browser.activeTabID = source.id
            XCTAssertTrue(browser.activeTab === source)
            XCTAssertEqual(changes.count, 1, "Selecting a different page must still invalidate its observers")
        }
    }

    func testPageSelectionTracksClosureRestorationAndInvalidIDs() throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        let first = try XCTUnwrap(browser.activeTab)
        browser.addTab()
        let second = try XCTUnwrap(browser.activeTab)
        browser.startSplitView(with: first.id)
        browser.closeTab(first.id)
        XCTAssertTrue(browser.activeTab === second)
        XCTAssertTrue(browser.splitTabs.isEmpty)

        browser.activeTabID = UUID()
        XCTAssertNil(browser.activeTab)
        browser.activeTabID = nil
        XCTAssertNil(browser.activeTab)
        browser.restoreSession(WindowSession(tabs: [
            TabSession(url: nil, title: "", interactionState: nil),
            TabSession(url: nil, title: "", interactionState: nil)
        ], selectedIndex: 1))
        XCTAssertTrue(browser.activeTab === browser.tabs[1])
        XCTAssertFalse(browser.activeTab === second)
        browser.releaseClosedWindow()
        XCTAssertNil(browser.activeTab)
        XCTAssertTrue(browser.splitTabs.isEmpty)
    }

    func testSelectedPagePropertiesStillNotifyObservers() throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        let tab = try XCTUnwrap(browser.activeTab)
        let changes = SelectionObservationCounter()
        withObservationTracking {
            _ = browser.activeTab?.isFindBarVisible
        } onChange: { MainActor.assumeIsolated { changes.count += 1 } }
        tab.isFindBarVisible = true
        XCTAssertEqual(changes.count, 1)
    }

    func testNewTabsStartWithoutLoadingAWebsite() {
        let browser = BrowserModel()

        XCTAssertTrue(browser.activeTab?.isNewTab == true)
        XCTAssertNil(browser.activeTab?.url)
        XCTAssertNil(browser.activeTab?.webView)
        XCTAssertFalse(browser.activeTab?.isSuspended ?? true)

        browser.addTab()

        XCTAssertEqual(browser.tabs.count, 2)
        XCTAssertTrue(browser.activeTab?.isNewTab == true)
        XCTAssertNil(browser.activeTab?.url)
        XCTAssertNil(browser.activeTab?.webView)
        browser.switchTab(by: -1)
        XCTAssertNil(browser.activeTab?.webView, "Selecting a native start page must not allocate WebKit")
    }

    func testFirstNavigationCreatesWebKitInTheOwningStoreAndSurvivesSuspension() throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        let tab = try XCTUnwrap(browser.activeTab)
        let container = tab.contentView
        browser.open(URL(string: "data:text/html,<title>First navigation</title>")!)
        let webView = try XCTUnwrap(tab.webView)
        XCTAssertTrue(webView.configuration.websiteDataStore === browser.websiteDataStore)
        XCTAssertTrue(webView.superview === container)
        XCTAssertFalse(tab.isNewTab)
        XCTAssertFalse(tab.isSuspended)
        tab.suspend()
        XCTAssertTrue(tab.isSuspended)
        tab.restore()
        XCTAssertNotNil(tab.webView)
        XCTAssertTrue(tab.webView?.configuration.websiteDataStore === browser.websiteDataStore)
        XCTAssertTrue(tab.contentView === container)
    }

    func testDuplicatedAndRestoredStartPagesStayNativeUntilNavigation() {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        browser.duplicateTab(browser.activeTabID!)
        browser.startSplitView()
        XCTAssertTrue(browser.tabs.allSatisfy { $0.webView == nil && !$0.isSuspended })
        browser.restoreSession(WindowSession(tabs: [
            TabSession(url: nil, title: "", interactionState: nil),
            TabSession(url: nil, title: "", interactionState: nil)
        ], selectedIndex: 1))
        XCTAssertTrue(browser.tabs.allSatisfy { $0.webView == nil && !$0.isSuspended })
    }

    func testTabShortcutsWrapAndSelectByNumber() {
        let browser = BrowserModel()
        browser.addTab()
        browser.addTab()

        browser.switchTab(by: 1)
        XCTAssertEqual(browser.activeTabID, browser.tabs[0].id)

        browser.switchTab(by: -1)
        XCTAssertEqual(browser.activeTabID, browser.tabs[2].id)

        browser.selectTab(at: 1)
        XCTAssertEqual(browser.activeTabID, browser.tabs[1].id)

        browser.selectLastTab()
        XCTAssertEqual(browser.activeTabID, browser.tabs[2].id)
    }

    func testReopenClosedBlankTab() {
        let browser = BrowserModel()
        let closedID = browser.activeTabID
        browser.closeActiveTab()

        browser.reopenClosedTab()

        XCTAssertEqual(browser.tabs.count, 2)
        XCTAssertNotEqual(browser.activeTabID, closedID)
        XCTAssertTrue(browser.activeTab?.isNewTab == true)
    }

    func testMoveTabReordersInBothDirections() {
        let browser = BrowserModel()
        browser.addTab()
        browser.addTab()
        let ids = browser.tabs.map(\.id)

        browser.moveTab(ids[0], to: 2)
        XCTAssertEqual(browser.tabs.map(\.id), [ids[1], ids[2], ids[0]])

        browser.moveTab(ids[0], to: 0)
        XCTAssertEqual(browser.tabs.map(\.id), ids)
    }

    func testCloseOtherTabsKeepsAndSelectsTheTab() {
        let browser = BrowserModel()
        browser.addTab()
        browser.addTab()
        let keptID = browser.tabs[1].id

        browser.closeOtherTabs(than: keptID)

        XCTAssertEqual(browser.tabs.map(\.id), [keptID])
        XCTAssertEqual(browser.activeTabID, keptID)
        XCTAssertTrue(browser.canReopenClosedTab)
    }

    func testCloseTabsToTheRightMovesSelectionWhenActiveTabCloses() {
        let browser = BrowserModel()
        browser.addTab()
        browser.addTab()
        let ids = browser.tabs.map(\.id)

        browser.closeTabs(after: ids[0])

        XCTAssertEqual(browser.tabs.map(\.id), [ids[0]])
        XCTAssertEqual(browser.activeTabID, ids[0])
    }

    func testDuplicateTabInsertsNextToOriginal() {
        let browser = BrowserModel()
        browser.addTab()
        let originalID = browser.tabs[0].id

        browser.duplicateTab(originalID)

        XCTAssertEqual(browser.tabs.count, 3)
        XCTAssertEqual(browser.tabs[0].id, originalID)
        XCTAssertEqual(browser.activeTabID, browser.tabs[1].id)
    }

    func testOpenInNewTabKeepsCurrentTab() {
        let browser = BrowserModel()
        let firstID = browser.activeTabID

        browser.open(URL(string: "https://swift.org")!, inNewTab: true)

        XCTAssertEqual(browser.tabs.count, 2)
        XCTAssertEqual(browser.tabs[0].id, firstID)
        XCTAssertEqual(browser.activeTabID, browser.tabs[1].id)
        XCTAssertFalse(browser.activeTab?.isNewTab ?? true)
    }
}

@MainActor
private final class SelectionObservationCounter {
    var count = 0
}
