import XCTest
@testable import Browser

@MainActor
final class BrowserModelTests: XCTestCase {
    func testNewTabsStartWithoutLoadingAWebsite() {
        let browser = BrowserModel()

        XCTAssertTrue(browser.activeTab?.isNewTab == true)
        XCTAssertNil(browser.activeTab?.url)

        browser.addTab()

        XCTAssertEqual(browser.tabs.count, 2)
        XCTAssertTrue(browser.activeTab?.isNewTab == true)
        XCTAssertNil(browser.activeTab?.url)
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
