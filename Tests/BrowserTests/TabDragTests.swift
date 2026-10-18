import XCTest
import Observation
@testable import Browser

@MainActor
final class TabDragTests: XCTestCase {
    func testAnimatedHeaderBoundsKeepVisualObserversQuietWithoutFreezingHitTesting() throws {
        for horizontal in [false, true] {
            let browser = BrowserModel.makePrivate()
            let drag = TabDragController()
            defer { drag.reset(); browser.releaseClosedWindow() }
            let source = try XCTUnwrap(browser.activeTab)
            let folder = browser.createGroup(name: "Target", color: .green)
            var header = TabDropRegion(id: "header", target: .group(folder),
                                       frame: CGRect(x: 0, y: 0, width: 20, height: 20), horizontal: horizontal)
            let point = CGPoint(x: 14, y: 14)
            drag.updateFrames(.init(regions: [header]), browser: browser)
            drag.update(id: source.id, location: point, browser: browser)
            let changes = DragObservationCounter()
            withObservationTracking {
                _ = drag.indicator
                _ = drag.location
                _ = drag.scrollRequest
            } onChange: { MainActor.assumeIsolated { changes.count += 1 } }
            // The header expands past the pointer's midpoint repeatedly, but its visual target
            // stays the same. Still retain every latest frame for release and hover validation.
            for sample in 0..<240 {
                header.frame.size = CGSize(width: 20 + sample % 20, height: 20 + sample % 20)
                drag.updateFrames(.init(regions: [header]), browser: browser)
                XCTAssertEqual(drag.selection?.region.frame, header.frame)
            }
            XCTAssertEqual(changes.count, 0, "Geometry-only changes must not invalidate the strip's visual observers")
            XCTAssertEqual(drag.indicator?.id, "header")
            XCTAssertEqual(drag.indicator?.after, false)
            drag.finish(id: source.id, location: point, browser: browser)
            XCTAssertEqual(source.groupID, folder)
            XCTAssertNil(drag.indicator)
            XCTAssertEqual(changes.count, 1, "Ending the drag must clear visual feedback")
        }
    }

    func testMovingChildMidpointUpdatesInsertionFeedbackInBothLayouts() throws {
        for horizontal in [false, true] {
            let browser = BrowserModel.makePrivate()
            let drag = TabDragController()
            defer { drag.reset(); browser.releaseClosedWindow() }
            let source = try XCTUnwrap(browser.activeTab)
            browser.addTab()
            let target = try XCTUnwrap(browser.activeTab)
            var region = TabDropRegion(id: "child", target: .tab(target.id),
                                       frame: CGRect(x: 0, y: 0, width: 100, height: 100), horizontal: horizontal)
            let point = CGPoint(x: 30, y: 30)
            drag.updateFrames(.init(regions: [region]), browser: browser)
            drag.update(id: source.id, location: point, browser: browser)
            XCTAssertEqual(drag.indicator?.after, false)
            region.frame.size = CGSize(width: 40, height: 40)
            drag.updateFrames(.init(regions: [region]), browser: browser)
            XCTAssertEqual(drag.indicator?.after, true, "Animated geometry crossing the pointer changes the insertion side")
            drag.finish(id: source.id, location: point, browser: browser)
            XCTAssertEqual(browser.tabs.map(\.id), [target.id, source.id])
        }
    }

    func testCollapsingChildBlocksStaleDropsUntilItsAnimatedFrameDisappears() throws {
        for horizontal in [false, true] {
            let browser = BrowserModel.makePrivate()
            let drag = TabDragController()
            defer { drag.reset(); browser.releaseClosedWindow() }
            let source = try XCTUnwrap(browser.activeTab)
            let original = browser.createGroup(name: "Source", color: .blue, tabID: source.id)
            browser.addTab()
            let child = try XCTUnwrap(browser.activeTab)
            let target = browser.createGroup(name: "Target", color: .green, tabID: child.id)
            browser.setPinned(horizontal, for: source.id)
            browser.setPinned(horizontal, for: child.id)
            let frame = CGRect(x: 0, y: 32, width: 120, height: 32)
            var frames = TabDragFrames(regions: [
                .init(id: "outside", target: .group(nil), frame: frame, horizontal: horizontal, priority: 0),
                .init(id: "child", target: .tab(child.id), frame: frame, horizontal: horizontal, priority: 2)
            ])
            let point = CGPoint(x: 30, y: 48)
            drag.updateFrames(frames, browser: browser)
            drag.update(id: source.id, location: point, browser: browser)
            XCTAssertEqual(drag.selection?.region.target, .tab(child.id))
            browser.collapseGroup(target)
            // The rendered exit transition may still publish the old card frame.
            drag.updateFrames(frames, browser: browser)
            XCTAssertNil(drag.selection)
            drag.finish(id: source.id, location: point, browser: browser)
            XCTAssertEqual(source.groupID, original)
            XCTAssertTrue(browser.groups[1].isCollapsed)

            browser.expandGroup(target)
            drag.update(id: source.id, location: point, browser: browser)
            XCTAssertEqual(drag.selection?.region.target, .tab(child.id), "Reversing collapse restores the target immediately")
            browser.collapseGroup(target)
            frames.regions.removeLast()
            drag.updateFrames(frames, browser: browser)
            XCTAssertEqual(drag.selection?.region.target, .group(nil), "Only the actual empty area accepts an outside drop")
            drag.finish(id: source.id, location: point, browser: browser)
            XCTAssertNil(source.groupID)
            XCTAssertEqual(source.isPinned, horizontal)
        }
    }

    func testTabHoverOpensFolderBeforeReleaseAndAllowsPreciseChildInsertion() async throws {
        for horizontal in [false, true] {
            let browser = BrowserModel.makePrivate()
            let drag = TabDragController()
            defer { drag.reset(); browser.releaseClosedWindow() }
            let source = try XCTUnwrap(browser.activeTab)
            let original = browser.createGroup(name: "Source", color: .blue, tabID: source.id)
            browser.addTab()
            let child = try XCTUnwrap(browser.activeTab)
            let target = browser.createGroup(name: "Target", color: .green, tabID: child.id)
            browser.setPinned(horizontal, for: source.id)
            browser.setPinned(horizontal, for: child.id)
            browser.activeTabID = source.id
            browser.toggleGroupCollapsed(target)
            let views = browser.tabs.map(\.webView)
            let ids = browser.tabs.map(\.id)
            let frame = CGRect(x: 0, y: 0, width: 120, height: 28)
            let frames = TabDragFrames(regions: [
                .init(id: "header", target: .group(target), frame: frame, horizontal: horizontal)
            ])
            drag.updateFrames(frames, browser: browser)
            drag.update(id: source.id, location: CGPoint(x: 30, y: 14), browser: browser)
            XCTAssertTrue(browser.groups[1].isCollapsed)
            try await Task.sleep(for: .milliseconds(300))
            // Pointer jitter and geometry refreshes inside this header must not restart the delay.
            drag.update(id: source.id, location: CGPoint(x: 31, y: 14), browser: browser)
            drag.updateFrames(frames, browser: browser)
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertFalse(browser.groups[1].isCollapsed)
            XCTAssertEqual(source.groupID, original)
            XCTAssertEqual(browser.activeTabID, source.id)
            XCTAssertEqual(browser.tabs.map(\.id), ids)
            XCTAssertEqual(browser.tabs.map(\.webView), views)
            XCTAssertTrue(drag.isDragging)
            let childFrame = horizontal ? CGRect(x: 124, y: 0, width: 100, height: 28)
                                        : CGRect(x: 0, y: 32, width: 120, height: 32)
            drag.updateFrames(.init(regions: frames.regions + [
                .init(id: "child", target: .tab(child.id), frame: childFrame, horizontal: horizontal, priority: 2)
            ]), browser: browser)
            let point = CGPoint(x: childFrame.minX + 5, y: childFrame.minY + 5)
            drag.finish(id: source.id, location: point, browser: browser)
            XCTAssertEqual(source.groupID, target)
            XCTAssertEqual(source.isPinned, horizontal)
            XCTAssertEqual(browser.tabs.map(\.id), [source.id, child.id])
            XCTAssertFalse(browser.groups[1].isCollapsed)
            drag.reset()
            XCTAssertFalse(browser.groups[1].isCollapsed)
        }
    }

    func testSpringLoadedFolderCoversChildrenAndGapsThenClosesOnExitInBothLayouts() async throws {
        for horizontal in [false, true] {
            let browser = BrowserModel.makePrivate()
            let drag = TabDragController()
            defer { drag.reset(); browser.releaseClosedWindow() }
            let source = try XCTUnwrap(browser.activeTab)
            browser.setPinned(true, for: source.id)
            browser.addTab()
            let child = try XCTUnwrap(browser.activeTab)
            let target = browser.createGroup(name: "Target", color: .green, tabID: child.id)
            browser.activeTabID = source.id
            browser.toggleGroupCollapsed(target)
            let header = TabDropRegion(id: "header", target: .group(target),
                                       frame: CGRect(x: 0, y: 0, width: 120, height: 28), horizontal: horizontal)
            drag.updateFrames(.init(regions: [header]), browser: browser)
            let start = CGPoint(x: 30, y: 14)
            drag.update(id: source.id, location: start, browser: browser)
            try await Task.sleep(for: .milliseconds(600))
            XCTAssertFalse(browser.groups[0].isCollapsed)
            let childFrame = horizontal ? CGRect(x: 124, y: 0, width: 100, height: 28)
                                        : CGRect(x: 0, y: 32, width: 120, height: 32)
            drag.updateFrames(.init(regions: [header,
                .init(id: "section", target: .groupOrder(target), frame: header.frame.union(childFrame), horizontal: horizontal),
                .init(id: "child", target: .tab(child.id), frame: childFrame, horizontal: horizontal, priority: 2)
            ]), browser: browser)
            let gap = horizontal ? CGPoint(x: 122, y: 14) : CGPoint(x: 30, y: 30)
            drag.update(id: source.id, location: gap, browser: browser)
            XCTAssertFalse(browser.groups[0].isCollapsed)
            drag.update(id: source.id, location: CGPoint(x: childFrame.midX, y: childFrame.midY), browser: browser)
            XCTAssertNil(drag.selection, "Pin cannot insert beside an ordinary child")
            XCTAssertFalse(browser.groups[0].isCollapsed, "Invalid child insertion is still inside the folder")
            drag.update(id: source.id, location: CGPoint(x: 500, y: 500), browser: browser)
            XCTAssertFalse(browser.groups[0].isCollapsed, "Leaving starts a grace period")
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertTrue(browser.groups[0].isCollapsed)
            XCTAssertNil(source.groupID)
            XCTAssertEqual(child.groupID, target)
            XCTAssertEqual(browser.activeTabID, source.id)
            drag.updateFrames(.init(regions: [header]), browser: browser)
            drag.update(id: source.id, location: start, browser: browser)
            try await Task.sleep(for: .milliseconds(600))
            XCTAssertFalse(browser.groups[0].isCollapsed, "Re-entry can spring-load the folder again")
            drag.cancel()
            XCTAssertTrue(browser.groups[0].isCollapsed)
        }
    }

    func testOpenedHoverFolderRestoresOnAbortedDropClippingOrRemoval() async throws {
        for interruption in ["cancel", "reset", "outside-release", "invalid-child-release", "clip", "remove-folder", "close-source"] {
            let browser = BrowserModel.makePrivate()
            let drag = TabDragController()
            defer { drag.reset(); browser.releaseClosedWindow() }
            let source = try XCTUnwrap(browser.activeTab)
            browser.setPinned(true, for: source.id)
            browser.addTab()
            let child = try XCTUnwrap(browser.activeTab)
            let target = browser.createGroup(name: "Target", color: .green, tabID: child.id)
            browser.activeTabID = source.id
            browser.toggleGroupCollapsed(target)
            let header = TabDropRegion(id: "header", target: .group(target), frame: CGRect(x: 0, y: 0, width: 120, height: 28),
                                       horizontal: false, viewport: "tabs")
            var frames = TabDragFrames(regions: [header], viewports: ["tabs": CGRect(x: 0, y: 0, width: 120, height: 100)])
            drag.updateFrames(frames, browser: browser)
            let point = CGPoint(x: 30, y: 14)
            drag.update(id: source.id, location: point, browser: browser)
            try await Task.sleep(for: .milliseconds(600))
            XCTAssertFalse(browser.groups[0].isCollapsed, interruption)
            switch interruption {
            case "cancel": drag.cancel()
            case "reset": drag.reset()
            case "outside-release": drag.finish(id: source.id, location: CGPoint(x: 500, y: 500), browser: browser)
            case "invalid-child-release":
                frames.regions.append(.init(id: "child", target: .tab(child.id), frame: CGRect(x: 0, y: 32, width: 120, height: 32),
                                             horizontal: false, viewport: "tabs", priority: 2))
                drag.updateFrames(frames, browser: browser)
                drag.finish(id: source.id, location: CGPoint(x: 30, y: 48), browser: browser)
            case "clip":
                frames.viewports["tabs"] = CGRect(x: 200, y: 200, width: 120, height: 100)
                drag.updateFrames(frames, browser: browser)
                XCTAssertFalse(browser.groups[0].isCollapsed, "Clipping also allows time to return")
                try await Task.sleep(for: .milliseconds(400))
            case "remove-folder": browser.ungroup(target); drag.reset()
            case "close-source":
                browser.setPinned(false, for: source.id)
                browser.closeTab(source.id)
                drag.finish(id: source.id, location: point, browser: browser)
            default: XCTFail("Unknown interruption")
            }
            XCTAssertTrue(browser.groups.allSatisfy(\.isCollapsed), interruption)
            XCTAssertNil(source.groupID, interruption)
        }
    }

    func testHeaderDropKeepsOnlyTheAcceptedSpringLoadedFolderOpen() async throws {
        let browser = BrowserModel.makePrivate()
        let drag = TabDragController()
        defer { drag.reset(); browser.releaseClosedWindow() }
        let source = try XCTUnwrap(browser.activeTab)
        let first = browser.createGroup(name: "First", color: .blue)
        let second = browser.createGroup(name: "Second", color: .green)
        browser.toggleGroupCollapsed(first)
        browser.toggleGroupCollapsed(second)
        drag.updateFrames(.init(regions: [
            .init(id: "first", target: .group(first), frame: CGRect(x: 0, y: 0, width: 120, height: 28), horizontal: false),
            .init(id: "second", target: .group(second), frame: CGRect(x: 0, y: 40, width: 120, height: 28), horizontal: false)
        ]), browser: browser)
        drag.update(id: source.id, location: CGPoint(x: 30, y: 14), browser: browser)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertFalse(browser.groups[0].isCollapsed)
        let destination = CGPoint(x: 30, y: 54)
        drag.update(id: source.id, location: destination, browser: browser)
        XCTAssertFalse(browser.groups[0].isCollapsed)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertTrue(browser.groups[0].isCollapsed)
        XCTAssertFalse(browser.groups[1].isCollapsed)
        drag.finish(id: source.id, location: destination, browser: browser)
        XCTAssertEqual(source.groupID, second)
        XCTAssertTrue(browser.groups[0].isCollapsed)
        XCTAssertFalse(browser.groups[1].isCollapsed)
    }

    func testReentryCancelsCollapseAndNextExitKeepsItsDeadlineInBothLayouts() async throws {
        for horizontal in [false, true] {
            let browser = BrowserModel.makePrivate()
            let drag = TabDragController()
            defer { drag.reset(); browser.releaseClosedWindow() }
            let source = try XCTUnwrap(browser.activeTab)
            browser.addTab()
            let child = try XCTUnwrap(browser.activeTab)
            let group = browser.createGroup(name: "Target", color: .green, tabID: child.id)
            browser.toggleGroupCollapsed(group)
            let header = CGRect(x: 0, y: 0, width: 120, height: 28)
            let childFrame = horizontal ? CGRect(x: 124, y: 0, width: 100, height: 28)
                                        : CGRect(x: 0, y: 32, width: 120, height: 32)
            let frames = TabDragFrames(regions: [
                .init(id: "header", target: .group(group), frame: header, horizontal: horizontal),
                .init(id: "section", target: .groupOrder(group), frame: header.union(childFrame), horizontal: horizontal),
                .init(id: "child", target: .tab(child.id), frame: childFrame, horizontal: horizontal, priority: 2)
            ])
            drag.updateFrames(frames, browser: browser)
            drag.update(id: source.id, location: CGPoint(x: 30, y: 14), browser: browser)
            try await Task.sleep(for: .milliseconds(600))
            XCTAssertFalse(browser.groups[0].isCollapsed)
            let gap = horizontal ? CGPoint(x: 122, y: 14) : CGPoint(x: 30, y: 30)
            // Every part of the section cancels an already-sleeping close task.
            for inside in [CGPoint(x: 30, y: 14), gap, CGPoint(x: childFrame.midX, y: childFrame.midY)] {
                drag.update(id: source.id, location: CGPoint(x: 500, y: 500), browser: browser)
                try await Task.sleep(for: .milliseconds(100))
                XCTAssertFalse(browser.groups[0].isCollapsed)
                drag.update(id: source.id, location: inside, browser: browser)
                try await Task.sleep(for: .milliseconds(400))
                XCTAssertFalse(browser.groups[0].isCollapsed, "Returning cancels the old deadline")
            }
            drag.update(id: source.id, location: CGPoint(x: 500, y: 500), browser: browser)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertFalse(browser.groups[0].isCollapsed, "A fresh exit receives a full grace period")
            drag.update(id: source.id, location: CGPoint(x: 501, y: 500), browser: browser)
            drag.updateFrames(frames, browser: browser)
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertTrue(browser.groups[0].isCollapsed, "Outside updates must not postpone closure")
            XCTAssertNil(source.groupID)
            XCTAssertEqual(child.groupID, group)
        }
    }

    func testPendingCollapseCannotAffectAcceptedDropOrLaterGesture() async throws {
        for ending in ["drop", "cancel", "reset", "outside-release"] {
            let browser = BrowserModel.makePrivate()
            let drag = TabDragController()
            defer { drag.reset(); browser.releaseClosedWindow() }
            let source = try XCTUnwrap(browser.activeTab)
            let group = browser.createGroup(name: "Target", color: .green)
            browser.toggleGroupCollapsed(group)
            let inside = CGPoint(x: 30, y: 14)
            let outside = CGPoint(x: 500, y: 500)
            drag.updateFrames(.init(regions: [
                .init(id: "header", target: .group(group), frame: CGRect(x: 0, y: 0, width: 120, height: 28), horizontal: false)
            ]), browser: browser)
            drag.update(id: source.id, location: inside, browser: browser)
            try await Task.sleep(for: .milliseconds(600))
            drag.update(id: source.id, location: outside, browser: browser)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertFalse(browser.groups[0].isCollapsed)
            switch ending {
            case "drop": drag.finish(id: source.id, location: inside, browser: browser)
            case "cancel": drag.cancel()
            case "reset": drag.reset()
            case "outside-release": drag.finish(id: source.id, location: outside, browser: browser)
            default: XCTFail("Unknown ending")
            }
            XCTAssertFalse(drag.isDragging)
            XCTAssertEqual(browser.groups[0].isCollapsed, ending != "drop")
            XCTAssertEqual(source.groupID, ending == "drop" ? group : nil)
            // A new gesture over a manually opened folder must not inherit the old close task.
            drag.reset()
            browser.expandGroup(group)
            drag.update(id: source.id, location: inside, browser: browser)
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertFalse(browser.groups[0].isCollapsed, ending)
            drag.update(id: source.id, location: outside, browser: browser)
            drag.cancel()
            XCTAssertFalse(browser.groups[0].isCollapsed, ending)
        }
    }

    func testAlreadyOpenOrIndependentlyOpenedFoldersAreNeverAutoCollapsed() async throws {
        for initiallyOpen in [true, false] {
            let browser = BrowserModel.makePrivate()
            let drag = TabDragController()
            defer { drag.reset(); browser.releaseClosedWindow() }
            let source = try XCTUnwrap(browser.activeTab)
            let group = browser.createGroup(name: "Open", color: .green)
            if !initiallyOpen { browser.toggleGroupCollapsed(group) }
            drag.updateFrames(.init(regions: [
                .init(id: "header", target: .group(group), frame: CGRect(x: 0, y: 0, width: 120, height: 28), horizontal: false)
            ]), browser: browser)
            drag.update(id: source.id, location: CGPoint(x: 30, y: 14), browser: browser)
            if !initiallyOpen { browser.expandGroup(group) }
            try await Task.sleep(for: .milliseconds(600))
            drag.update(id: source.id, location: CGPoint(x: 500, y: 500), browser: browser)
            drag.cancel()
            XCTAssertFalse(browser.groups[0].isCollapsed)
            XCTAssertNil(source.groupID)
        }
    }

    func testHoverExpansionCancelsWhenLeavingClippingResettingOrEndingDrag() async throws {
        for interruption in ["leave", "clip", "cancel", "reset", "release", "close-source", "remove-folder"] {
            let browser = BrowserModel.makePrivate()
            let drag = TabDragController()
            defer { drag.reset(); browser.releaseClosedWindow() }
            let tab = try XCTUnwrap(browser.activeTab)
            let target = browser.createGroup(name: "Target", color: .green)
            browser.toggleGroupCollapsed(target)
            let frame = CGRect(x: 0, y: 0, width: 120, height: 28)
            var frames = TabDragFrames(regions: [
                .init(id: "header", target: .group(target), frame: frame, horizontal: false, viewport: "tabs")
            ], viewports: ["tabs": frame])
            drag.updateFrames(frames, browser: browser)
            drag.update(id: tab.id, location: CGPoint(x: 30, y: 14), browser: browser)
            // Let the task start before interrupting it, exercising cancellation of a sleeping task.
            await Task.yield()
            switch interruption {
            case "leave": drag.update(id: tab.id, location: CGPoint(x: 300, y: 300), browser: browser)
            case "clip":
                frames.viewports["tabs"] = CGRect(x: 200, y: 200, width: 120, height: 28)
                drag.updateFrames(frames, browser: browser)
            case "cancel": drag.cancel()
            case "reset": drag.reset()
            case "release": drag.finish(id: tab.id, location: CGPoint(x: 300, y: 300), browser: browser)
            case "close-source": browser.closeTab(tab.id)
            case "remove-folder": browser.ungroup(target)
            default: XCTFail("Unknown interruption")
            }
            try await Task.sleep(for: .milliseconds(600))
            XCTAssertTrue(browser.groups.allSatisfy(\.isCollapsed), interruption)
            XCTAssertNil(tab.groupID, interruption)
        }
    }

    func testRetargetedHoverOpensOnlyLatestFolderAndFolderDragsNeverExpand() async throws {
        let browser = BrowserModel.makePrivate()
        let drag = TabDragController()
        defer { drag.reset(); browser.releaseClosedWindow() }
        let tab = try XCTUnwrap(browser.activeTab)
        let first = browser.createGroup(name: "First", color: .blue)
        let second = browser.createGroup(name: "Second", color: .green)
        browser.toggleGroupCollapsed(first)
        browser.toggleGroupCollapsed(second)
        let firstPoint = CGPoint(x: 30, y: 14)
        let secondPoint = CGPoint(x: 30, y: 50)
        drag.updateFrames(.init(regions: [
            .init(id: "first", target: .group(first), frame: CGRect(x: 0, y: 0, width: 120, height: 28), horizontal: false),
            .init(id: "second", target: .group(second), frame: CGRect(x: 0, y: 36, width: 120, height: 28), horizontal: false),
            .init(id: "section", target: .groupOrder(second), frame: CGRect(x: 0, y: 36, width: 120, height: 28), horizontal: false)
        ]), browser: browser)
        drag.update(id: tab.id, location: firstPoint, browser: browser)
        await Task.yield()
        drag.update(id: tab.id, location: secondPoint, browser: browser)
        await Task.yield()
        drag.update(id: tab.id, location: firstPoint, browser: browser)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertFalse(browser.groups[0].isCollapsed)
        XCTAssertTrue(browser.groups[1].isCollapsed)
        drag.cancel()
        drag.reset()
        drag.updateGroup(id: first, location: secondPoint, browser: browser)
        XCTAssertEqual(drag.selection?.region.target, .groupOrder(second))
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertTrue(browser.groups[1].isCollapsed)
        XCTAssertEqual(browser.groups.map(\.id), [first, second])
        XCTAssertNil(tab.groupID)
    }

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

@MainActor
private final class DragObservationCounter {
    var count = 0
}
