import XCTest
@testable import Browser

@MainActor
final class BrowserModelTests: XCTestCase {
    func testNewTabsStartWithoutLoadingAWebsite() {
        let browser = BrowserModel()

        XCTAssertTrue(browser.activeTab?.isNewTab == true)
        XCTAssertNil(browser.activeTab?.page.url)

        browser.addTab()

        XCTAssertEqual(browser.tabs.count, 2)
        XCTAssertTrue(browser.activeTab?.isNewTab == true)
        XCTAssertNil(browser.activeTab?.page.url)
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
}
