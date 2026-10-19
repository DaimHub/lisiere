import AppKit
import WebKit
import XCTest
@testable import Browser

@MainActor
final class TabWindowDragTests: XCTestCase {
    @MainActor private final class Windows {
        let suite = "TabWindowDragTests.\(UUID())"
        let defaults: UserDefaults
        let profiles: ProfileStore
        let source: ProfileWindowController
        let target: ProfileWindowController
        let sourceWindow: NSWindow
        let targetWindow: NSWindow
        let sourceView: TabDragCoordinateView
        let targetView: TabDragCoordinateView
        let sourceDrag = TabDragController()
        let targetDrag = TabDragController()

        init(differentProfile: Bool = false) throws {
            defaults = UserDefaults(suiteName: suite)!
            let store = WKWebsiteDataStore(forIdentifier: UUID())
            profiles = ProfileStore(root: nil, defaults: defaults, dataStoreFactory: { _ in store })
            source = try ProfileWindowController(profiles: profiles, profileID: BrowserProfile.initialID)
            let targetID = differentProfile ? try profiles.create(name: "Other").id : BrowserProfile.initialID
            target = try ProfileWindowController(profiles: profiles, profileID: targetID)
            let screen = NSScreen.main!.visibleFrame
            let width = min(420, (screen.width - 160) / 2)
            let size = CGSize(width: width, height: 360)
            sourceWindow = NSWindow(contentRect: CGRect(origin: CGPoint(x: screen.minX + 40, y: screen.minY + 60), size: size),
                                    styleMask: [.titled, .closable], backing: .buffered, defer: true)
            targetWindow = NSWindow(contentRect: CGRect(origin: CGPoint(x: screen.minX + 80 + width, y: screen.minY + 60), size: size),
                                    styleMask: [.titled, .closable], backing: .buffered, defer: true)
            sourceWindow.isReleasedWhenClosed = false
            targetWindow.isReleasedWhenClosed = false
            sourceView = TabDragCoordinateView(frame: CGRect(origin: .zero, size: size))
            targetView = TabDragCoordinateView(frame: CGRect(origin: .zero, size: size))
            sourceWindow.contentView = sourceView
            targetWindow.contentView = targetView
            source.connect(sourceWindow)
            target.connect(targetWindow)
            sourceDrag.connect(sourceView, browser: source.browser)
            targetDrag.connect(targetView, browser: target.browser)
            for (drag, browser) in [(sourceDrag, source.browser), (targetDrag, target.browser)] {
                drag.updateFrames(.init(pageFrame: CGRect(x: 0, y: 80, width: width, height: 280),
                                        windowFrame: CGRect(origin: .zero, size: size)), browser: browser)
            }
            targetWindow.orderFront(nil)
            sourceWindow.makeKeyAndOrderFront(nil)
        }

        func show() async throws {
            NSApp.activate()
            targetWindow.display()
            sourceWindow.display()
            targetWindow.orderFrontRegardless()
            sourceWindow.orderFrontRegardless()
            let point = targetWindow.convertPoint(toScreen: targetView.convert(CGPoint(x: 100, y: 100), to: nil))
            try await waitUntil { NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0) == self.targetWindow.windowNumber }
        }

        func point(_ local: CGPoint, from target: NSView, in source: NSView) -> CGPoint {
            let screen = target.window!.convertPoint(toScreen: target.convert(local, to: nil))
            return source.convert(source.window!.convertPoint(fromScreen: screen), from: nil)
        }

        func close() {
            sourceDrag.disconnect(sourceView)
            targetDrag.disconnect(targetView)
            source.close(); target.close()
            sourceWindow.close(); targetWindow.close()
            for profile in profiles.profiles {
                profiles.context(for: profile.id)?.prepareForDeletion()
                if !profile.isInitial { defaults.removePersistentDomain(forName: ProfileStore.defaultsDomain(for: profile.id)) }
            }
            defaults.removePersistentDomain(forName: suite)
        }
    }

    func testFloatingCardFollowsScreenCoordinatesOutsideWindowAndNeverTakesFocus() async throws {
        let windows = try Windows()
        defer { windows.close() }
        try await windows.show()
        let id = try XCTUnwrap(windows.source.browser.activeTabID)
        let point = CGPoint(x: -240, y: -100)
        let key = NSApp.keyWindow
        windows.sourceDrag.update(id: id, location: point, browser: windows.source.browser)
        let panel = try XCTUnwrap(windows.sourceDrag.floatingPreview?.window)
        let screen = windows.sourceWindow.convertPoint(toScreen: windows.sourceView.convert(point, to: nil))
        XCTAssertEqual(panel.frame.midX, screen.x + 20, accuracy: 1)
        XCTAssertEqual(panel.frame.midY, screen.y - 20, accuracy: 1)
        XCTAssertFalse(windows.sourceWindow.frame.intersects(panel.frame))
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertTrue(NSApp.keyWindow === key)
        windows.sourceDrag.cancel()
        XCTAssertFalse(panel.isVisible)
        XCTAssertNil(windows.sourceDrag.floatingPreview)
    }

    func testTabReturnsToExistingWindowAndClosesItsEmptySourceWithoutCreatingBlankTabs() async throws {
        let windows = try Windows()
        defer { windows.close() }
        try await windows.show()
        let source = windows.source.browser, target = windows.target.browser
        let tab = try XCTUnwrap(source.activeTab)
        source.open(URL(string: "data:text/html,<title>Moving</title><input id='draft'>")!)
        try await waitUntil { tab.pageTitle == "Moving" && !tab.isLoading }
        let webView = try XCTUnwrap(tab.webView)
        _ = try await webView.evaluateJavaScript("document.getElementById('draft').value='round trip'")
        source.addTab()
        let remaining = try XCTUnwrap(source.activeTab)
        source.open(URL(string: "data:text/html,<title>Remaining</title>")!)
        try await waitUntil { remaining.pageTitle == "Remaining" && !remaining.isLoading }
        let group = source.createGroup(name: "Destination group", color: .green, tabID: remaining.id)
        windows.sourceDrag.updateFrames(.init(regions: [
            .init(id: remaining.id.uuidString, target: .tab(remaining.id),
                  frame: CGRect(x: 10, y: 0, width: 120, height: 50), horizontal: true)
        ], pageFrame: CGRect(x: 0, y: 80, width: 420, height: 280),
           windowFrame: windows.sourceView.bounds), browser: source)
        var detached = false
        windows.sourceDrag.detachTab = { _, _ in detached = true }
        let intoTarget = windows.point(CGPoint(x: 100, y: 20), from: windows.targetView, in: windows.sourceView)
        windows.sourceDrag.update(id: tab.id, location: intoTarget, browser: source)
        XCTAssertEqual(windows.sourceDrag.pageDrop, .existingWindow)
        XCTAssertTrue(source.tabs.contains { $0 === tab }, "Hover must not transfer ownership")
        // Let the floating panel reach the window server before checking that it remains transparent to drops.
        try await Task.sleep(for: .milliseconds(100))
        let screenPoint = windows.targetWindow.convertPoint(toScreen: windows.targetView.convert(CGPoint(x: 100, y: 20), to: nil))
        XCTAssertEqual(NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: 0), windows.targetWindow.windowNumber)
        windows.sourceDrag.finish(id: tab.id, location: intoTarget, browser: source)
        XCTAssertFalse(detached)
        XCTAssertTrue(target.activeTab === tab)
        XCTAssertTrue(source.activeTab === remaining)
        XCTAssertTrue(windows.sourceWindow.isVisible)

        let back = windows.point(CGPoint(x: 100, y: 20), from: windows.sourceView, in: windows.targetView)
        windows.targetDrag.update(id: tab.id, location: back, browser: target)
        windows.targetDrag.finish(id: tab.id, location: back, browser: target)
        XCTAssertTrue(source.activeTab === tab)
        XCTAssertTrue(tab.webView === webView)
        XCTAssertEqual(source.tabs.count, 2)
        XCTAssertEqual(source.tabs.map(\.id), [remaining.id, tab.id])
        XCTAssertEqual(tab.groupID, group)
        XCTAssertTrue(windows.target.isClosed)
        XCTAssertFalse(windows.targetWindow.isVisible)
        XCTAssertTrue(target.tabs.isEmpty)
        XCTAssertFalse(source.canReopenClosedTab)
        let draft = try await webView.evaluateJavaScript("document.getElementById('draft').value") as? String
        XCTAssertEqual(draft, "round trip")
        let session = try XCTUnwrap(windows.profiles.session(for: BrowserProfile.initialID)?.snapshot)
        XCTAssertEqual(session.windows.count, 1)
        XCTAssertEqual(session.windows.first?.tabs.count, 2)
        XCTAssertTrue(session.closedWindows.isEmpty)
    }

    func testOtherWindowPageDropShowsSplitAndEscapeLeavesBothWindowsUntouched() async throws {
        let windows = try Windows()
        defer { windows.close() }
        try await windows.show()
        let source = windows.source.browser, target = windows.target.browser
        target.open(URL(string: "data:text/html,<title>Destination</title>")!)
        let partner = try XCTUnwrap(target.activeTab)
        try await waitUntil { partner.pageTitle == "Destination" && !partner.isLoading }
        let tab = try XCTUnwrap(source.activeTab)
        let point = windows.point(CGPoint(x: 30, y: 160), from: windows.targetView, in: windows.sourceView)
        windows.sourceDrag.update(id: tab.id, location: point, browser: source)
        XCTAssertEqual(windows.targetDrag.pageDrop, .split(.leading))
        windows.sourceDrag.cancel()
        windows.sourceDrag.finish(id: tab.id, location: point, browser: source)
        XCTAssertNil(windows.targetDrag.pageDrop)
        XCTAssertTrue(source.activeTab === tab)
        XCTAssertTrue(target.activeTab === partner)
        XCTAssertFalse(target.isSplitView)

        windows.sourceDrag.update(id: tab.id, location: point, browser: source)
        windows.sourceDrag.finish(id: tab.id, location: point, browser: source)
        XCTAssertEqual(target.splitTabIDs, [tab.id, partner.id])
        XCTAssertTrue(target.activeTab === tab)
        XCTAssertTrue(windows.source.isClosed)
        XCTAssertFalse(windows.sourceWindow.isVisible)
    }

    func testDifferentProfileWindowRejectsDropInsteadOfOpeningAnotherWindow() async throws {
        let windows = try Windows(differentProfile: true)
        defer { windows.close() }
        try await windows.show()
        let source = windows.source.browser
        let tab = try XCTUnwrap(source.activeTab)
        var detached = false
        windows.sourceDrag.detachTab = { _, _ in detached = true }
        let point = windows.point(CGPoint(x: 100, y: 120), from: windows.targetView, in: windows.sourceView)
        windows.sourceDrag.update(id: tab.id, location: point, browser: source)
        XCTAssertEqual(windows.sourceDrag.pageDrop, .unavailableWindow)
        windows.sourceDrag.finish(id: tab.id, location: point, browser: source)
        XCTAssertFalse(detached)
        XCTAssertTrue(source.activeTab === tab)
        XCTAssertTrue(windows.sourceWindow.isVisible)
        XCTAssertTrue(windows.targetWindow.isVisible)
    }
}
