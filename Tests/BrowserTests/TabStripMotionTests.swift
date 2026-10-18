import AppKit
import SwiftUI
import Observation
import XCTest
@testable import Browser

/// Exercise the real SwiftUI layout and the same animated bounds consumed by tab dragging.
/// These are geometry/interaction regressions, not display-refresh or GPU benchmarks.
@MainActor
final class TabStripMotionTests: XCTestCase {
    func testContinuousPointerMovementDuringDisclosurePreservesTargetsAndSelection() async throws {
        for layout in [TabLayout.vertical, .horizontal] {
            for pinned in [false, true] {
                let fixture = try MotionFixture(layout: layout, pinned: pinned)
                defer { fixture.close() }
                try await fixture.settle()
                fixture.recording.begin()
                let childID = fixture.children[0].id
                for sample in 0..<120 {
                    if sample % 20 == 0 { fixture.browser.toggleGroupCollapsed(fixture.folder) }
                    let region = try fixture.recording.latest.regions.first { $0.target == .tab(childID) }
                        ?? fixture.region(fixture.folderRegion)
                    let point = CGPoint(x: region.frame.midX + CGFloat(sample % 3), y: region.frame.midY)
                    fixture.drag.update(id: fixture.source.id, location: point, browser: fixture.browser)
                    XCTAssertEqual(fixture.drag.location, point)
                    XCTAssertNil(fixture.source.groupID, "Pointer motion must not commit a move before release")
                    try await Task.sleep(for: .milliseconds(8))
                }
                fixture.drag.cancel()
                try await fixture.settle()
                fixture.assertIdentity()
                XCTAssertNil(fixture.drag.selection)
                fixture.recording.report("continuous-\(layout)-pins-\(pinned)")
            }
        }
    }

    func testHoverGeometryTracksOnlyTheRequestedPreviewAcrossDisclosure() async throws {
        for layout in [TabLayout.vertical, .horizontal] {
            let fixture = try MotionFixture(layout: layout, pinned: true)
            defer { fixture.close() }
            try await fixture.settle()
            XCTAssertTrue(fixture.recording.hoverTabIDs.isEmpty)
            let id = fixture.children[0].id
            fixture.hoverPreview.tabID = id
            try await fixture.waitUntil { fixture.recording.hoverTabIDs == [id] }
            fixture.browser.collapseGroup(fixture.folder)
            try await fixture.waitUntil { fixture.recording.hoverTabIDs.isEmpty }
            fixture.browser.expandGroup(fixture.folder)
            try await fixture.waitUntil { fixture.recording.hoverTabIDs == [id] }
            fixture.hoverPreview.tabID = nil
            try await fixture.waitUntil { fixture.recording.hoverTabIDs.isEmpty }
            fixture.assertIdentity()
        }
    }

    func testRapidDisclosureReversalsKeepIntermediateGeometryAndTabIdentity() async throws {
        for layout in [TabLayout.vertical, .horizontal] {
            for pinned in [false, true] {
                let fixture = try MotionFixture(layout: layout, pinned: pinned)
                defer { fixture.close() }
                try await fixture.settle()
                let expanded = try fixture.neighborPosition()
                fixture.browser.collapseGroup(fixture.folder)
                try await fixture.settle()
                let collapsed = try fixture.neighborPosition()
                XCTAssertGreaterThan(abs(expanded - collapsed), 20)
                fixture.recording.begin()

                // Retarget while moving, rather than sleeping until the previous transition ends.
                for _ in 0..<3 {
                    fixture.browser.expandGroup(fixture.folder)
                    try await fixture.waitUntil {
                        guard let position = try? fixture.neighborPosition() else { return false }
                        return position > collapsed + (expanded - collapsed) * 0.2
                    }
                    let reversal = try fixture.neighborPosition()
                    XCTAssertLessThan(reversal, expanded - 1)
                    fixture.browser.collapseGroup(fixture.folder)
                    try await fixture.waitUntil {
                        guard let position = try? fixture.neighborPosition() else { return false }
                        return position < collapsed + (expanded - collapsed) * 0.1
                    }
                }
                try await fixture.settle()
                XCTAssertEqual(try fixture.neighborPosition(), collapsed, accuracy: 0.5)
                let positions = fixture.recording.positions(for: fixture.neighborRegion, layout: layout)
                XCTAssertGreaterThan(positions.filter { $0 > collapsed + 1 && $0 < expanded - 1 }.count, 6)
                XCTAssertTrue(positions.allSatisfy { $0 >= collapsed - 1 && $0 <= expanded + 1 }, "Rapid reversals must not overshoot folder endpoints")
                let largestStep = zip(positions, positions.dropFirst()).map { abs($0 - $1) }.max() ?? 0
                XCTAssertLessThan(largestStep, (expanded - collapsed) * 0.5, "Disclosure must not jump directly between endpoints")
                fixture.assertIdentity()
                fixture.recording.report("rapid-\(layout)-pins-\(pinned)")
            }
        }
    }

    func testSpringLoadedDragUsesAnimatedBoundsAcrossExitReentryAndDrop() async throws {
        for layout in [TabLayout.vertical, .horizontal] {
            for pinned in [false, true] {
                let fixture = try MotionFixture(layout: layout, pinned: pinned)
                defer { fixture.close() }
                fixture.browser.collapseGroup(fixture.folder)
                try await fixture.settle()
                let collapsed = try fixture.neighborPosition()
                let header = try fixture.region(fixture.folderRegion).frame
                let inside = CGPoint(x: header.midX, y: header.midY)
                fixture.drag.update(id: fixture.source.id, location: inside, browser: fixture.browser)
                fixture.recording.begin()
                try await fixture.waitUntil { !fixture.browser.groups[0].isCollapsed }
                try await fixture.waitUntil { ((try? fixture.neighborPosition()) ?? collapsed) > collapsed + 2 }
                XCTAssertEqual(fixture.drag.selection?.region.target, .group(fixture.folder))
                try await fixture.settle()
                let expanded = try fixture.neighborPosition()
                XCTAssertGreaterThan(expanded, collapsed + 20)

                let outside = CGPoint(x: -40, y: -40)
                fixture.drag.update(id: fixture.source.id, location: outside, browser: fixture.browser)
                try await Task.sleep(for: .milliseconds(100))
                fixture.drag.update(id: fixture.source.id, location: inside, browser: fixture.browser)
                try await Task.sleep(for: .milliseconds(250))
                XCTAssertFalse(fixture.browser.groups[0].isCollapsed, "Re-entry must cancel the pending close while bounds are updating")
                fixture.drag.update(id: fixture.source.id, location: outside, browser: fixture.browser)
                try await fixture.waitUntil { fixture.browser.groups[0].isCollapsed }
                try await fixture.waitUntil { ((try? fixture.neighborPosition()) ?? expanded) < expanded - 2 }
                try await fixture.settle()
                XCTAssertEqual(try fixture.neighborPosition(), collapsed, accuracy: 0.5)
                fixture.drag.update(id: fixture.source.id, location: inside, browser: fixture.browser)
                try await fixture.waitUntil { !fixture.browser.groups[0].isCollapsed }
                // Release over a child while its folder is still opening. Use its current rendered bounds.
                let childID = fixture.children[0].id
                try await fixture.waitUntil { fixture.recording.latest.regions.contains { $0.target == .tab(childID) } }
                let child = try XCTUnwrap(fixture.recording.latest.regions.first { $0.target == .tab(childID) })
                let point = CGPoint(x: child.frame.midX, y: child.frame.midY)
                fixture.drag.update(id: fixture.source.id, location: point, browser: fixture.browser)
                XCTAssertEqual(fixture.drag.selection?.region.target, .tab(childID))
                fixture.drag.finish(id: fixture.source.id, location: point, browser: fixture.browser)
                try await fixture.settle()
                XCTAssertEqual(fixture.source.groupID, fixture.folder)
                XCTAssertEqual(fixture.source.isPinned, pinned)
                XCTAssertFalse(fixture.browser.groups[0].isCollapsed)
                XCTAssertFalse(fixture.drag.isDragging)
                XCTAssertGreaterThan(fixture.recording.positions(for: fixture.neighborRegion, layout: layout)
                    .filter { $0 > collapsed + 1 && $0 < expanded - 1 }.count, 3)
                fixture.assertIdentity()
                fixture.recording.report("drag-\(layout)-pins-\(pinned)")
            }
        }
    }
}

@MainActor
private final class MotionFixture {
    let browser = BrowserModel.makePrivate()
    let drag = TabDragController()
    let recording = MotionRecording()
    let hoverPreview = HoverPreviewProbe()
    let layout: TabLayout
    let folder: UUID
    let neighbor: UUID
    let source: BrowserTab
    let children: [BrowserTab]
    let window: NSWindow
    let folderRegion: String
    let neighborRegion: String
    let originalTabs: [BrowserTab]
    let activeID: UUID?

    init(layout: TabLayout, pinned: Bool) throws {
        self.layout = layout
        let first = try XCTUnwrap(browser.activeTab)
        folder = browser.createGroup(name: "First", color: .green, tabID: first.id)
        for _ in 0..<3 { browser.addTab(in: folder) }
        children = browser.tabs
        browser.addTab()
        neighbor = browser.createGroup(name: "Neighbor", color: .blue, tabID: try XCTUnwrap(browser.activeTab).id)
        browser.addTab()
        source = try XCTUnwrap(browser.activeTab)
        if pinned { for tab in browser.tabs { browser.setPinned(true, for: tab.id) } }
        originalTabs = browser.tabs
        activeID = browser.activeTabID
        folderRegion = "\(pinned)-\(folder)"
        neighborRegion = "\(pinned)-\(neighbor)"
        let size = layout == .vertical ? CGSize(width: 240, height: 900) : CGSize(width: 1800, height: 44)
        window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let recording = recording
        let hoverPreview = hoverPreview
        let strip = TabStrip(browser: browser, layout: layout, isFullScreen: true, accent: .blue,
                             hoverCardTabID: Binding(get: { hoverPreview.tabID }, set: { hoverPreview.tabID = $0 }), drag: drag)
            .overlayPreferenceValue(TabDragBoundsKey.self) { bounds in
                GeometryReader { geometry in
                    let frames = bounds.resolve(in: geometry)
                    Color.clear.onChange(of: frames, initial: true) { _, value in recording.append(value) }
                }
            }
            .overlayPreferenceValue(TabFrameKey.self) { anchors in
                Color.clear.onChange(of: Set(anchors.keys), initial: true) { _, ids in recording.hoverTabIDs = ids }
            }
        // This test supplies preview selection explicitly. Ignore real pointer hover: a CI cursor over
        // the newly opened window must not schedule a competing delayed preview.
        window.ignoresMouseEvents = true
        window.setFrameOrigin(CGPoint(x: -4000, y: -4000))
        // Exercise intermediate geometry even when the runner has Reduce Motion enabled.
        // Scope the app's motion override to this fixture; leave macOS preferences unchanged.
        window.contentView = NSHostingView(rootView: strip
            .environment(\.browserReduceMotion, false))
        window.orderFront(nil)
    }

    func region(_ id: String) throws -> TabDropRegion { try XCTUnwrap(recording.latest.regions.first { $0.id == id }) }
    func neighborPosition() throws -> CGFloat {
        let frame = try region(neighborRegion).frame
        return layout == .horizontal ? frame.minX : frame.minY
    }
    func settle() async throws { try await Task.sleep(for: .milliseconds(600)) }
    func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while !predicate(), ProcessInfo.processInfo.systemUptime < deadline { try await Task.sleep(for: .milliseconds(5)) }
        guard predicate() else {
            XCTFail("Native animated layout did not reach the requested intermediate state")
            throw MotionTimeout()
        }
    }
    func assertIdentity(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(browser.activeTabID, activeID, file: file, line: line)
        XCTAssertEqual(Set(browser.tabs.map(\.id)), Set(originalTabs.map(\.id)), file: file, line: line)
        for tab in originalTabs { XCTAssertTrue(browser.tab(withID: tab.id) === tab, file: file, line: line) }
    }
    func close() {
        drag.reset()
        window.orderOut(nil)
        window.contentView = nil
        window.close()
        browser.releaseClosedWindow()
    }
}

@MainActor
private final class MotionRecording {
    struct Entry { var time: TimeInterval; var frames: TabDragFrames }
    var entries: [Entry] = []
    var latest = TabDragFrames()
    var hoverTabIDs: Set<UUID> = []
    private var startCPU = clock()
    func begin() {
        entries.removeAll()
        startCPU = clock()
    }
    func append(_ frames: TabDragFrames) {
        latest = frames
        entries.append(Entry(time: ProcessInfo.processInfo.systemUptime, frames: frames))
    }
    func positions(for id: String, layout: TabLayout) -> [CGFloat] {
        entries.compactMap { entry in
            entry.frames.regions.first { $0.id == id }.map { layout == .horizontal ? $0.frame.minX : $0.frame.minY }
        }
    }
    func report(_ label: String) {
        let cpuMilliseconds = Double(clock() - startCPU) * 1_000 / Double(CLOCKS_PER_SEC)
        print("MOTION \(label): \(entries.count) native geometry updates, \(Int(cpuMilliseconds)) ms process CPU")
    }
}

@MainActor @Observable
private final class HoverPreviewProbe { var tabID: UUID? }

private struct MotionTimeout: Error {}
