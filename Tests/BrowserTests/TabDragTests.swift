import XCTest
@testable import Browser

@MainActor
final class TabDragTests: XCTestCase {
    func testFolderDragUsesSectionBoundsAndLayoutAxisAndCommitsOnlyOnRelease() throws {
        for horizontal in [false, true] {
            let browser = BrowserModel.makePrivate()
            let drag = TabDragController()
            defer { drag.reset(); browser.releaseClosedWindow() }
            let first = browser.createGroup(name: "First", color: .blue)
            let second = browser.createGroup(name: "Second", color: .green)
            let third = browser.createGroup(name: "Third", color: .purple)
            browser.toggleGroupCollapsed(first)
            let tab = try XCTUnwrap(browser.activeTab)
            browser.assignTab(tab.id, to: third)
            let frame = CGRect(x: 0, y: 0, width: 200, height: 100)
            // A child card must not turn a folder move into a membership edit.
            drag.updateFrames(.init(regions: [
                .init(id: "section", target: .groupOrder(third), frame: frame, horizontal: horizontal),
                .init(id: "card", target: .tab(tab.id), frame: frame, horizontal: horizontal, priority: 2)
            ]), browser: browser)
            let point = horizontal ? CGPoint(x: 190, y: 10) : CGPoint(x: 10, y: 90)
            drag.updateGroup(id: first, location: point, browser: browser)
            XCTAssertEqual(drag.selection?.region.target, .groupOrder(third))
            XCTAssertEqual(drag.selection?.after, true)
            XCTAssertEqual(browser.groups.map(\.id), [first, second, third])
            drag.finishGroup(id: first, location: point, browser: browser)
            XCTAssertEqual(browser.groups.map(\.id), [second, third, first])
            XCTAssertTrue(browser.groups[2].isCollapsed)
            XCTAssertEqual(tab.groupID, third)
            XCTAssertFalse(drag.isDragging)
            let before = CGPoint(x: 10, y: 10)
            drag.updateGroup(id: first, location: before, browser: browser)
            drag.finishGroup(id: first, location: before, browser: browser)
            XCTAssertEqual(browser.groups.map(\.id), [second, first, third])
        }
    }

    func testFolderCancellationOutsideAndSelfDropsDoNotReorderOrUngroup() throws {
        let browser = BrowserModel.makePrivate()
        let drag = TabDragController()
        defer { drag.reset(); browser.releaseClosedWindow() }
        let tab = try XCTUnwrap(browser.activeTab)
        let first = browser.createGroup(name: "First", color: .blue, tabID: tab.id)
        let second = browser.createGroup(name: "Second", color: .green)
        let frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        let point = CGPoint(x: 100, y: 90)
        for target in [TabDropTarget.group(first), .groupOrder(first)] {
            drag.updateFrames(.init(regions: [.init(id: "target", target: target, frame: frame, horizontal: false)]), browser: browser)
            drag.updateGroup(id: first, location: point, browser: browser)
            XCTAssertNil(drag.selection)
            drag.finishGroup(id: first, location: point, browser: browser)
            XCTAssertEqual(browser.groups.map(\.id), [first, second])
        }
        drag.updateFrames(.init(regions: [.init(id: "target", target: .groupOrder(second), frame: frame, horizontal: false)]), browser: browser)
        drag.updateGroup(id: first, location: point, browser: browser)
        drag.cancel()
        drag.updateGroup(id: first, location: point, browser: browser)
        drag.finishGroup(id: first, location: point, browser: browser)
        XCTAssertEqual(browser.groups.map(\.id), [first, second])
        drag.updateGroup(id: first, location: point, browser: browser)
        drag.finishGroup(id: first, location: CGPoint(x: 500, y: 500), browser: browser)
        XCTAssertEqual(browser.groups.map(\.id), [first, second])
        XCTAssertEqual(tab.groupID, first)
    }

    func testClippedFolderSectionCannotInterceptAnotherViewport() throws {
        let browser = BrowserModel.makePrivate()
        let drag = TabDragController()
        defer { drag.reset(); browser.releaseClosedWindow() }
        let first = browser.createGroup(name: "First", color: .blue)
        let second = browser.createGroup(name: "Second", color: .green)
        let third = browser.createGroup(name: "Third", color: .purple)
        let frame = CGRect(x: 0, y: 100, width: 220, height: 28)
        drag.updateFrames(.init(regions: [
            .init(id: "hidden", target: .groupOrder(second), frame: frame, horizontal: false, viewport: "pins", priority: 2),
            .init(id: "visible", target: .groupOrder(third), frame: frame, horizontal: false, viewport: "tabs")
        ], viewports: ["pins": CGRect(x: 0, y: 0, width: 220, height: 50),
                      "tabs": CGRect(x: 0, y: 80, width: 220, height: 200)]), browser: browser)
        let point = CGPoint(x: 100, y: 125)
        drag.updateGroup(id: first, location: point, browser: browser)
        XCTAssertEqual(drag.selection?.region.id, "visible")
        drag.finishGroup(id: first, location: point, browser: browser)
        XCTAssertEqual(browser.groups.map(\.id), [second, third, first])
    }

    func testEmptySpaceMovesFolderToEndInBothLayoutsOnlyOnRelease() throws {
        for horizontal in [false, true] {
            let browser = BrowserModel.makePrivate()
            let drag = TabDragController()
            defer { drag.reset(); browser.releaseClosedWindow() }
            let pin = try XCTUnwrap(browser.activeTab)
            let first = browser.createGroup(name: "First", color: .blue, tabID: pin.id)
            browser.setPinned(true, for: pin.id)
            browser.toggleGroupCollapsed(first)
            let second = browser.createGroup(name: "Second", color: .green)
            let third = browser.createGroup(name: "Third", color: .purple)
            let original = browser.groups[0]
            let frame = horizontal ? CGRect(x: 600, y: 0, width: 200, height: 44)
                                   : CGRect(x: 0, y: 200, width: 220, height: 400)
            let point = CGPoint(x: frame.midX, y: frame.midY)
            drag.updateFrames(.init(regions: [
                .init(id: "background", target: .group(nil), frame: frame, horizontal: horizontal, priority: 0)
            ]), browser: browser)
            drag.updateGroup(id: first, location: point, browser: browser)
            XCTAssertEqual(drag.selection?.region.target, .group(nil))
            XCTAssertEqual(browser.groups.map(\.id), [first, second, third])
            drag.finishGroup(id: first, location: point, browser: browser)
            XCTAssertEqual(browser.groups.map(\.id), [second, third, first])
            XCTAssertEqual(browser.groups.last, original)
            XCTAssertEqual(pin.groupID, first)
            XCTAssertTrue(pin.isPinned)
            XCTAssertEqual(browser.activeTabID, pin.id)
            // Already last remains a no-op, and cancellation must not commit an otherwise valid drop.
            drag.updateGroup(id: first, location: point, browser: browser)
            drag.finishGroup(id: first, location: point, browser: browser)
            drag.updateGroup(id: second, location: point, browser: browser)
            drag.cancel()
            drag.finishGroup(id: second, location: point, browser: browser)
            XCTAssertEqual(browser.groups.map(\.id), [second, third, first])
        }
    }

    func testOccupiedRegionsBlockFolderDropThroughToEmptySpace() throws {
        let browser = BrowserModel.makePrivate()
        let drag = TabDragController()
        defer { drag.reset(); browser.releaseClosedWindow() }
        let tab = try XCTUnwrap(browser.activeTab)
        let first = browser.createGroup(name: "First", color: .blue)
        let second = browser.createGroup(name: "Second", color: .green)
        let frame = CGRect(x: 0, y: 100, width: 220, height: 40)
        let point = CGPoint(x: 100, y: 120)
        let background = TabDropRegion(id: "background", target: .group(nil), frame: frame, horizontal: false, priority: 0)
        for target in [TabDropTarget.tab(tab.id), .groupOrder(first), .group(first)] {
            drag.updateFrames(.init(regions: [background,
                .init(id: "occupied", target: target, frame: frame, horizontal: false, priority: 2)
            ]), browser: browser)
            drag.updateGroup(id: first, location: point, browser: browser)
            XCTAssertNil(drag.selection)
            drag.finishGroup(id: first, location: point, browser: browser)
            XCTAssertEqual(browser.groups.map(\.id), [first, second])
        }
        // Offscreen content no longer occupies the blank area in the other scroll section.
        drag.updateFrames(.init(regions: [background,
            .init(id: "clipped", target: .groupOrder(first), frame: frame, horizontal: false, viewport: "pins")
        ], viewports: ["pins": CGRect(x: 0, y: 0, width: 220, height: 50)]), browser: browser)
        drag.updateGroup(id: first, location: point, browser: browser)
        XCTAssertEqual(drag.selection?.region.id, "background")
        drag.finishGroup(id: first, location: point, browser: browser)
        XCTAssertEqual(browser.groups.map(\.id), [second, first])
        XCTAssertNil(tab.groupID)
    }

    func testPointerDropIntoFolderCommitsOnlyOnRelease() throws {
        let browser = BrowserModel.makePrivate()
        let drag = TabDragController()
        defer { drag.reset(); browser.releaseClosedWindow() }
        let tab = try XCTUnwrap(browser.activeTab)
        let first = browser.createGroup(name: "First", color: .blue, tabID: tab.id)
        let second = browser.createGroup(name: "Second", color: .green)
        browser.toggleGroupCollapsed(second)
        drag.updateFrames(.init(regions: [
            .init(id: "section", target: .groupOrder(second), frame: CGRect(x: 0, y: 60, width: 220, height: 60), horizontal: false, priority: 3),
            .init(id: "folder", target: .group(second), frame: CGRect(x: 0, y: 60, width: 220, height: 28), horizontal: false)
        ]), browser: browser)
        drag.update(id: tab.id, location: CGPoint(x: 100, y: 70), browser: browser)
        XCTAssertEqual(drag.selection?.region.target, .group(second))
        XCTAssertEqual(tab.groupID, first)
        let view = tab.webView
        drag.finish(id: tab.id, location: CGPoint(x: 100, y: 70), browser: browser)
        XCTAssertEqual(tab.groupID, second)
        XCTAssertFalse(browser.groups[1].isCollapsed)
        XCTAssertTrue(tab.webView === view)
        XCTAssertEqual(browser.activeTabID, tab.id)
        XCTAssertNil(drag.sourceID)
    }

    func testDroppingPinOnEmptySidebarRemovesOnlyMembership() throws {
        let browser = BrowserModel.makePrivate()
        let drag = TabDragController()
        defer { drag.reset(); browser.releaseClosedWindow() }
        let tab = try XCTUnwrap(browser.activeTab)
        browser.createGroup(name: "Work", color: .blue, tabID: tab.id)
        browser.setPinned(true, for: tab.id)
        drag.updateFrames(.init(regions: [
            .init(id: "background", target: .group(nil), frame: CGRect(x: 0, y: 46, width: 236, height: 500), horizontal: false, priority: 0)
        ]), browser: browser)
        drag.update(id: tab.id, location: CGPoint(x: 100, y: 300), browser: browser)
        drag.finish(id: tab.id, location: CGPoint(x: 100, y: 300), browser: browser)
        XCTAssertNil(tab.groupID)
        XCTAssertTrue(tab.isPinned)
        XCTAssertEqual(browser.tabs.count, 1)
    }

    func testEscapeAndOutsideDropLeaveMembershipUnchanged() throws {
        let browser = BrowserModel.makePrivate()
        let drag = TabDragController()
        defer { drag.reset(); browser.releaseClosedWindow() }
        let id = try XCTUnwrap(browser.activeTabID)
        let group = browser.createGroup(name: "Work", color: .blue, tabID: id)
        let point = CGPoint(x: 50, y: 50)
        drag.updateFrames(.init(regions: [
            .init(id: "outside", target: .group(nil), frame: CGRect(x: 0, y: 0, width: 100, height: 100), horizontal: false)
        ]), browser: browser)
        drag.update(id: id, location: point, browser: browser)
        drag.cancel()
        drag.update(id: id, location: point, browser: browser)
        drag.finish(id: id, location: point, browser: browser)
        XCTAssertEqual(browser.activeTab?.groupID, group)
        drag.update(id: id, location: point, browser: browser)
        drag.finish(id: id, location: CGPoint(x: 500, y: 500), browser: browser)
        XCTAssertEqual(browser.activeTab?.groupID, group)
        XCTAssertNil(drag.selection)
    }

    func testClippedTabsDoNotStealFolderDropsAndInvalidTabsDoNotUngroup() throws {
        let browser = BrowserModel.makePrivate()
        let drag = TabDragController()
        defer { drag.reset(); browser.releaseClosedWindow() }
        let pin = try XCTUnwrap(browser.activeTab)
        let group = browser.createGroup(name: "Work", color: .blue, tabID: pin.id)
        browser.setPinned(true, for: pin.id)
        browser.addTab()
        let regular = try XCTUnwrap(browser.activeTabID)
        let frame = CGRect(x: 0, y: 100, width: 220, height: 32)
        drag.updateFrames(.init(regions: [
            .init(id: "hidden", target: .tab(regular), frame: frame, horizontal: false, viewport: "pins", priority: 2),
            .init(id: "folder", target: .group(group), frame: frame, horizontal: false),
            .init(id: "background", target: .group(nil), frame: frame, horizontal: false, priority: 0)
        ], viewports: ["pins": CGRect(x: 0, y: 0, width: 220, height: 50)]), browser: browser)
        let point = CGPoint(x: 100, y: 110)
        drag.update(id: pin.id, location: point, browser: browser)
        XCTAssertEqual(drag.selection?.region.id, "folder")
        drag.updateFrames(.init(regions: [
            .init(id: "regular", target: .tab(regular), frame: frame, horizontal: false, priority: 2),
            .init(id: "background", target: .group(nil), frame: frame, horizontal: false, priority: 0)
        ]), browser: browser)
        XCTAssertNil(drag.selection)
        drag.finish(id: pin.id, location: point, browser: browser)
        XCTAssertEqual(pin.groupID, group)
    }

    func testScrollDirectionUsesLayoutRatherThanViewportSize() throws {
        let browser = BrowserModel.makePrivate()
        let drag = TabDragController()
        defer { drag.reset(); browser.releaseClosedWindow() }
        let id = try XCTUnwrap(browser.activeTabID)
        let frame = CGRect(x: 0, y: 0, width: 220, height: 36)
        let point = CGPoint(x: 110, y: 35)
        drag.updateFrames(.init(viewports: ["pins": frame]), browser: browser)
        drag.update(id: id, location: point, browser: browser)
        XCTAssertEqual(drag.scrollRequest, .init(viewport: "pins", forward: true, horizontal: false))
        drag.updateFrames(.init(viewports: ["pins": frame], horizontalViewports: ["pins"]), browser: browser)
        XCTAssertNil(drag.scrollRequest)
        drag.update(id: id, location: CGPoint(x: 219, y: 18), browser: browser)
        XCTAssertEqual(drag.scrollRequest, .init(viewport: "pins", forward: true, horizontal: true))
    }

    func testGeometrySelectsInsertionSideAndNextOffscreenTabForScrolling() throws {
        let browser = BrowserModel.makePrivate()
        let drag = TabDragController()
        defer { drag.reset(); browser.releaseClosedWindow() }
        let first = try XCTUnwrap(browser.activeTabID)
        browser.addTab()
        let second = try XCTUnwrap(browser.activeTabID)
        drag.updateFrames(.init(regions: [
            .init(id: "second", target: .tab(second), frame: CGRect(x: 0, y: 80, width: 220, height: 32), horizontal: false, viewport: "tabs", priority: 2)
        ], viewports: ["tabs": CGRect(x: 0, y: 0, width: 220, height: 100)]), browser: browser)
        drag.update(id: first, location: CGPoint(x: 100, y: 98), browser: browser)
        XCTAssertEqual(drag.selection?.after, true)
        let request = try XCTUnwrap(drag.scrollRequest)
        XCTAssertTrue(request.forward)
        XCTAssertEqual(drag.nextScrollTarget(request), AnyHashable(second))
        drag.finish(id: first, location: CGPoint(x: 100, y: 98), browser: browser)
        XCTAssertEqual(browser.tabs.map(\.id), [second, first])
    }
}
