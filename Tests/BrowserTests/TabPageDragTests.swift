import AppKit
import WebKit
import XCTest
@testable import Browser

@MainActor
final class TabPageDragTests: XCTestCase {
    private let page = CGRect(x: 200, y: 90, width: 800, height: 600)
    private let bounds = CGRect(x: 0, y: 0, width: 1010, height: 700)

    func testPageDropsChooseSideWithoutReorderingTabsOrDiscardingReplacedPane() throws {
        let browser = BrowserModel.makePrivate()
        let drag = TabDragController()
        defer { drag.reset(); browser.releaseClosedWindow() }
        browser.addTab()
        browser.addTab()
        let ids = browser.tabs.map(\.id)
        drag.updateFrames(.init(pageFrame: page, windowFrame: bounds), browser: browser)
        drag.update(id: ids[0], location: CGPoint(x: 250, y: 200), browser: browser)
        XCTAssertEqual(drag.pageDrop, .split(.leading))
        drag.finish(id: ids[0], location: CGPoint(x: 250, y: 200), browser: browser)
        XCTAssertEqual(browser.splitTabIDs, [ids[0], ids[2]])
        XCTAssertEqual(browser.activeTabID, ids[0])
        drag.update(id: ids[1], location: CGPoint(x: 900, y: 200), browser: browser)
        drag.finish(id: ids[1], location: CGPoint(x: 900, y: 200), browser: browser)
        XCTAssertEqual(browser.splitTabIDs, [ids[0], ids[1]])
        XCTAssertEqual(browser.tabs.map(\.id), ids)
        browser.splitTab(ids[1], on: .leading)
        XCTAssertEqual(browser.splitTabIDs, [ids[1], ids[0]])
        XCTAssertNil(drag.pageDrop)
    }

    func testCurrentSinglePageAndGroupsCannotSplitAndEscapeCancels() throws {
        let browser = BrowserModel.makePrivate()
        let drag = TabDragController()
        defer { drag.reset(); browser.releaseClosedWindow() }
        let id = try XCTUnwrap(browser.activeTabID)
        let folder = browser.createGroup(name: "Folder", color: .green)
        drag.updateFrames(.init(pageFrame: page, windowFrame: bounds), browser: browser)
        let point = CGPoint(x: 300, y: 300)
        drag.update(id: id, location: point, browser: browser)
        XCTAssertNil(drag.pageDrop)
        drag.finish(id: id, location: point, browser: browser)
        XCTAssertFalse(browser.isSplitView)
        browser.addTab()
        drag.updateGroup(id: folder, location: point, browser: browser)
        XCTAssertNil(drag.pageDrop)
        drag.finishGroup(id: folder, location: point, browser: browser)
        drag.update(id: id, location: point, browser: browser)
        XCTAssertNotNil(drag.pageDrop)
        drag.cancel()
        drag.finish(id: id, location: point, browser: browser)
        XCTAssertFalse(browser.isSplitView)
        XCTAssertNil(drag.location)
    }

    func testOutsideDropUsesScreenCoordinatesAndInsideChromeDoesNothing() throws {
        let browser = BrowserModel.makePrivate()
        let drag = TabDragController()
        let window = NSWindow(contentRect: CGRect(x: 100, y: 150, width: 1010, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: true)
        let view = TabDragCoordinateView(frame: bounds)
        window.contentView = view
        browser.window = window
        drag.coordinateView = view
        defer { drag.reset(); browser.releaseClosedWindow(); window.contentView = nil }
        let id = try XCTUnwrap(browser.activeTabID)
        var detached: (UUID, CGPoint)?
        drag.detachTab = { detached = ($0, $1) }
        drag.updateFrames(.init(pageFrame: page, windowFrame: bounds), browser: browser)
        drag.update(id: id, location: CGPoint(x: 500, y: 50), browser: browser)
        XCTAssertNil(drag.pageDrop, "Toolbar is not an external drop")
        drag.update(id: id, location: CGPoint(x: 1015, y: 200), browser: browser)
        XCTAssertNil(drag.pageDrop, "Keep a small margin beyond the window edge")
        let outside = CGPoint(x: 1100, y: 200)
        drag.update(id: id, location: outside, browser: browser)
        XCTAssertEqual(drag.pageDrop, .newWindow)
        drag.finish(id: id, location: outside, browser: browser)
        XCTAssertEqual(detached?.0, id)
        XCTAssertEqual(detached?.1, window.convertPoint(toScreen: view.convert(outside, to: nil)))
        XCTAssertFalse(drag.isDragging)
        detached = nil
        drag.update(id: id, location: outside, browser: browser)
        drag.cancel()
        drag.finish(id: id, location: outside, browser: browser)
        XCTAssertNil(detached)
    }

    func testMovingLiveTabPreservesFormHistoryViewAndPrivateCookies() async throws {
        let source = BrowserModel.makePrivate()
        let destination = BrowserModel(websiteDataStore: source.websiteDataStore)
        let unrelated = BrowserModel.makePrivate()
        defer { source.releaseClosedWindow(); destination.releaseClosedWindow(); unrelated.releaseClosedWindow() }
        let tab = try XCTUnwrap(source.activeTab)
        source.open(URL(string: "data:text/html,<title>Before</title><p>One</p>")!)
        try await waitUntil { tab.pageTitle == "Before" && !tab.isLoading }
        source.open(URL(string: "data:text/html,<title>Moving</title><input id='draft'>")!)
        try await waitUntil { tab.pageTitle == "Moving" && tab.canGoBack && !tab.isLoading }
        let view = try XCTUnwrap(tab.webView)
        _ = try await view.evaluateJavaScript("document.getElementById('draft').value='keep this draft'")
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "example.com", .path: "/", .name: "session", .value: "private"]))
        await source.websiteDataStore.httpCookieStore.setCookie(cookie)
        XCTAssertTrue(source.moveTab(tab.id, to: destination))
        XCTAssertTrue(destination.activeTab === tab)
        XCTAssertTrue(tab.webView === view)
        XCTAssertTrue(tab.browser === destination)
        XCTAssertTrue(tab.canGoBack)
        let draft = try await view.evaluateJavaScript("document.getElementById('draft').value") as? String
        XCTAssertEqual(draft, "keep this draft")
        XCTAssertTrue(source.activeTab?.isNewTab == true)
        XCTAssertFalse(source.canReopenClosedTab)
        source.releaseClosedWindow()
        let cookies = await destination.websiteDataStore.httpCookieStore.allCookies()
        XCTAssertTrue(cookies.contains { $0.name == "session" && $0.value == "private" })
        let otherCookies = await unrelated.websiteDataStore.httpCookieStore.allCookies()
        XCTAssertTrue(otherCookies.isEmpty)
        destination.goBack()
        try await waitUntil { tab.pageTitle == "Before" && !tab.isLoading }
    }

    func testMovePreservesPinnedGroupAndDissolvesOnlyItsSplit() throws {
        let source = BrowserModel.makePrivate()
        let destination = BrowserModel(websiteDataStore: source.websiteDataStore)
        defer { source.releaseClosedWindow(); destination.releaseClosedWindow() }
        let first = try XCTUnwrap(source.activeTab)
        let group = source.createGroup(name: "Research", color: .green, tabID: first.id)
        source.setPinned(true, for: first.id)
        source.startSplitView()
        let partner = try XCTUnwrap(source.activeTab)
        XCTAssertTrue(source.moveTab(first.id, to: destination))
        XCTAssertFalse(source.hasSplitPair)
        XCTAssertTrue(source.activeTab === partner)
        XCTAssertTrue(destination.activeTab === first)
        XCTAssertTrue(first.isPinned)
        XCTAssertEqual(first.groupID, group)
        XCTAssertEqual(destination.groups.first?.name, "Research")
        XCTAssertEqual(destination.tabs.count, 1)
    }

    func testPrivateAndProfileBoundariesAndPendingDecisionRejectTransfer() throws {
        let source = BrowserModel.makePrivate()
        let unrelated = BrowserModel.makePrivate()
        let compatible = BrowserModel(websiteDataStore: source.websiteDataStore)
        defer { source.releaseClosedWindow(); unrelated.releaseClosedWindow(); compatible.releaseClosedWindow() }
        let tab = try XCTUnwrap(source.activeTab)
        XCTAssertFalse(source.moveTab(tab.id, to: unrelated))
        let prompt = tab.beginPasswordPrompt()
        XCTAssertFalse(source.moveTab(tab.id, to: compatible))
        XCTAssertNil(TabWindowTransfer.prepare(tabID: tab.id, source: source, at: .zero))
        XCTAssertTrue(tab.isPasswordPromptPending(prompt))
        tab.finishPasswordPrompt(prompt)
        XCTAssertTrue(source.moveTab(tab.id, to: compatible))
    }

    func testTransferWaitsForNativeWindowAndCannotBeConsumedTwice() throws {
        let suite = "TabPageDragTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let profiles = ProfileStore(root: nil, defaults: defaults)
        let source = try ProfileWindowController(profiles: profiles, profileID: BrowserProfile.initialID, isPrivate: true)
        let tab = try XCTUnwrap(source.browser.activeTab)
        let token = try XCTUnwrap(TabWindowTransfer.prepare(tabID: tab.id, source: source.browser, at: CGPoint(x: 500, y: 500)))
        let destination = try ProfileWindowController(profiles: profiles, profileID: BrowserProfile.initialID,
                                                      isPrivate: true, tabTransferID: token)
        defer { source.close(); destination.close(); defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(source.browser.activeTab === tab)
        XCTAssertNil(TabWindowTransfer.take(token, profileID: BrowserProfile.initialID, isPrivate: true))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: true)
        defer { window.orderOut(nil) }
        destination.connect(window)
        XCTAssertTrue(destination.browser.activeTab === tab)
        XCTAssertTrue(tab.webView?.configuration.websiteDataStore === destination.browser.websiteDataStore)
        XCTAssertTrue(source.browser.activeTab?.isNewTab == true)
    }

    func testSuspendedTabDetachesAndRestoresInItsOriginalSession() async throws {
        let source = BrowserModel.makePrivate()
        let destination = BrowserModel(websiteDataStore: source.websiteDataStore)
        defer { source.releaseClosedWindow(); destination.releaseClosedWindow() }
        let tab = try XCTUnwrap(source.activeTab)
        source.open(URL(string: "data:text/html,<title>Suspended</title>")!)
        try await waitUntil { tab.pageTitle == "Suspended" && !tab.isLoading }
        source.addTab()
        tab.suspend()
        XCTAssertTrue(tab.isSuspended)
        XCTAssertTrue(source.moveTab(tab.id, to: destination))
        try await waitUntil { !tab.isSuspended && !tab.isLoading && tab.pageTitle == "Suspended" }
        XCTAssertTrue(destination.activeTab === tab)
        XCTAssertTrue(tab.webView?.configuration.websiteDataStore === destination.websiteDataStore)
    }

    func testDepartingHostCannotStealLastTabBackFromItsNewWindow() async throws {
        let source = BrowserModel.makePrivate()
        let destination = BrowserModel(websiteDataStore: source.websiteDataStore)
        let tab = try XCTUnwrap(source.activeTab)
        let oldWindow = NSWindow(contentRect: bounds, styleMask: [.titled], backing: .buffered, defer: true)
        let newWindow = NSWindow(contentRect: bounds, styleMask: [.titled], backing: .buffered, defer: true)
        let oldHost = PageHostView(), newHost = PageHostView()
        oldWindow.contentView = oldHost
        newWindow.contentView = newHost
        defer {
            oldHost.releaseContent(); newHost.releaseContent()
            oldWindow.contentView = nil; newWindow.contentView = nil
            source.releaseClosedWindow(); destination.releaseClosedWindow()
        }
        oldHost.show(tab.contentView, tab: tab, browser: source)
        XCTAssertTrue(tab.contentView.window === oldWindow)
        XCTAssertTrue(source.moveTab(tab.id, to: destination))
        newHost.show(tab.contentView, tab: tab, browser: destination)
        // SwiftUI updates an outgoing host while its source fades to the new-tab page.
        oldHost.show(tab.contentView, tab: tab, browser: source)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(tab.contentView.window === newWindow)
        XCTAssertTrue(tab.webView?.window === newWindow)
        oldHost.releaseContent()
        XCTAssertTrue(tab.contentView.window === newWindow)
    }

    func testDetachedWindowStaysInsideTheDestinationScreenIncludingNegativeOrigins() {
        let screen = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
        for point in [CGPoint(x: -1900, y: -280), CGPoint(x: -50, y: 760)] {
            let frame = TabWindowTransfer.frame(for: CGSize(width: 1000, height: 700), at: point, screens: [screen])
            XCTAssertTrue(screen.contains(frame))
        }
    }
}
