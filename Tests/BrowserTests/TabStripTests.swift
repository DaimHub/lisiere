import XCTest
@testable import Browser

final class TabStripTests: XCTestCase {
    func testPinnedTilesFillTheFinalRowWithoutExceedingThreeColumns() {
        let metrics = PinnedTabGridMetrics(count: 5, width: 220)
        XCTAssertEqual(metrics.columns, 3)
        XCTAssertEqual(metrics.rows, 2)
        XCTAssertEqual(metrics.frame(at: 2).maxX, 220, accuracy: 0.001)
        XCTAssertEqual(metrics.frame(at: 4).maxX, 220, accuracy: 0.001)
        XCTAssertGreaterThan(metrics.frame(at: 3).width, metrics.frame(at: 0).width)
        XCTAssertEqual(metrics.frame(at: 4).maxY, metrics.height)
        XCTAssertEqual(PinnedTabGridMetrics(count: 12, width: 600).columns, 3)
    }

    func testPinnedGridHandlesEmptyAndNarrowSidebarsWithoutClipping() {
        for width: CGFloat in [0, 48, 116, 220] {
            XCTAssertEqual(PinnedTabGridMetrics(count: 0, width: width).height, 0)
            let metrics = PinnedTabGridMetrics(count: 8, width: width)
            for index in 0..<metrics.count {
                let frame = metrics.frame(at: index)
                XCTAssertGreaterThanOrEqual(frame.minX, 0)
                XCTAssertLessThanOrEqual(frame.maxX, width + 0.001)
                XCTAssertGreaterThanOrEqual(frame.width, 0)
                XCTAssertLessThanOrEqual(frame.maxY, metrics.height)
            }
        }
    }

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
        XCTAssertFalse(metrics.showsOverflowMenu)
    }

    func testResizingReservesAddButtonAndDragAreaBeforeScrolling() {
        let wide = HorizontalTabStripMetrics(tabCount: 8, width: 1440, leading: 85)
        let narrow = HorizontalTabStripMetrics(tabCount: 8, width: 680, leading: 85)
        let overflow = HorizontalTabStripMetrics(tabCount: 30, width: 680, leading: 85)
        XCTAssertGreaterThan(wide.tabWidth, narrow.tabWidth)
        XCTAssertFalse(wide.scrolls)
        XCTAssertTrue(narrow.scrolls)
        XCTAssertTrue(narrow.showsOverflowMenu)
        XCTAssertTrue(overflow.scrolls)
        XCTAssertEqual(overflow.tabWidth, 120)
        XCTAssertEqual(overflow.viewportWidth, 680 - 85 - BrowserChrome.edgeInset
                       - HorizontalTabStripMetrics.addButtonSize - HorizontalTabStripMetrics.dragAreaWidth
                       - HorizontalTabStripMetrics.overflowButtonSize - HorizontalTabStripMetrics.spacing * 3)
    }

    func testOverflowAppearsOnlyWhenReadableTabsNoLongerFit() {
        let controls = CGFloat(85) + BrowserChrome.edgeInset + HorizontalTabStripMetrics.addButtonSize
            + HorizontalTabStripMetrics.dragAreaWidth + HorizontalTabStripMetrics.spacing * 2
        let content = CGFloat(4 * 120) + HorizontalTabStripMetrics.spacing * 3 + 124
        let fits = HorizontalTabStripMetrics(tabCount: 4, width: controls + content, leading: 85, supplementaryWidth: 124)
        let overflows = HorizontalTabStripMetrics(tabCount: 4, width: controls + content - 1, leading: 85, supplementaryWidth: 124)
        XCTAssertFalse(fits.showsOverflowMenu)
        XCTAssertFalse(fits.scrolls)
        XCTAssertTrue(overflows.showsOverflowMenu)
        XCTAssertTrue(overflows.scrolls)
        XCTAssertEqual(fits.contentWidth, overflows.contentWidth, "Overflow must preserve readable tab widths")
        XCTAssertGreaterThanOrEqual(overflows.tabWidth, 120)
    }

    func testPinnedOverflowKeepsTheTabListAvailableWithoutRegularTabs() {
        let metrics = HorizontalTabStripMetrics(tabCount: 0, width: 680, leading: 85, pinnedTabsOverflow: true)
        XCTAssertTrue(metrics.showsOverflowMenu)
        XCTAssertEqual(metrics.viewportWidth, 0)
        XCTAssertFalse(metrics.scrolls)
    }

    func testFullScreenUsesSpaceFreedByTheWindowControls() {
        let windowed = HorizontalTabStripMetrics(tabCount: 30, width: 680, leading: 85)
        let fullScreen = HorizontalTabStripMetrics(tabCount: 30, width: 680, leading: BrowserChrome.edgeInset)
        XCTAssertGreaterThan(fullScreen.viewportWidth, windowed.viewportWidth)
        XCTAssertTrue(fullScreen.scrolls)
    }
}
