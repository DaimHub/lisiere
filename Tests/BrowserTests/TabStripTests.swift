import XCTest
@testable import Browser

final class TabStripTests: XCTestCase {
    func testEmptyStripHasFiniteNonnegativeDimensions() {
        for width: CGFloat in [0, 680, 1440] {
            let metrics = HorizontalTabStripMetrics(tabCount: 0, width: width, leading: 85)
            XCTAssertEqual(metrics.tabWidth, 0)
            XCTAssertEqual(metrics.contentWidth, 0)
            XCTAssertEqual(metrics.viewportWidth, 0)
            XCTAssertFalse(metrics.scrolls)
        }
    }

    func testSingleTabKeepsTheAddButtonNextToItsCard() {
        let metrics = HorizontalTabStripMetrics(tabCount: 1, width: 1440, leading: 85)
        XCTAssertEqual(metrics.tabWidth, 220)
        XCTAssertEqual(metrics.viewportWidth, metrics.tabWidth)
        XCTAssertFalse(metrics.scrolls)
    }

    func testResizingReservesAddButtonAndDragAreaBeforeScrolling() {
        let wide = HorizontalTabStripMetrics(tabCount: 8, width: 1440, leading: 85)
        let narrow = HorizontalTabStripMetrics(tabCount: 8, width: 680, leading: 85)
        let overflow = HorizontalTabStripMetrics(tabCount: 30, width: 680, leading: 85)
        XCTAssertGreaterThan(wide.tabWidth, narrow.tabWidth)
        XCTAssertFalse(narrow.scrolls)
        XCTAssertTrue(overflow.scrolls)
        XCTAssertEqual(overflow.tabWidth, 56)
        XCTAssertEqual(overflow.viewportWidth, 680 - 85 - BrowserChrome.edgeInset
                       - HorizontalTabStripMetrics.addButtonSize - HorizontalTabStripMetrics.dragAreaWidth
                       - HorizontalTabStripMetrics.spacing * 2)
    }

    func testFullScreenUsesSpaceFreedByTheWindowControls() {
        let windowed = HorizontalTabStripMetrics(tabCount: 30, width: 680, leading: 85)
        let fullScreen = HorizontalTabStripMetrics(tabCount: 30, width: 680, leading: BrowserChrome.edgeInset)
        XCTAssertGreaterThan(fullScreen.viewportWidth, windowed.viewportWidth)
        XCTAssertTrue(fullScreen.scrolls)
    }
}
