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
}
