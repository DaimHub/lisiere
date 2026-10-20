import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import Browser

@MainActor
final class SplitViewTests: XCTestCase {
    private func page(_ title: String) -> URL {
        URL(string: "data:text/html,<title>\(title)</title><input id='draft'>")!
    }

    func testNewPaneAndExistingTabReuseExactlyTwoPages() throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        browser.open(page("First"))
        let first = try XCTUnwrap(browser.activeTab)
        let firstView = first.webView
        browser.startSplitView()
        let second = try XCTUnwrap(browser.activeTab)
        browser.open(page("Second"))
        XCTAssertEqual(browser.splitTabIDs, [first.id, second.id])
        XCTAssertEqual(browser.tabs.count, 2)
        XCTAssertTrue(first.webView === firstView)
        XCTAssertTrue(browser.splitTabs.allSatisfy { $0.webView?.configuration.websiteDataStore === browser.websiteDataStore })
        browser.startSplitView(with: first.id)
        XCTAssertEqual(browser.tabs.count, 2)
        XCTAssertEqual(browser.splitTabIDs, [second.id, first.id])
        browser.startSplitView(with: first.id)
        browser.startSplitView(with: UUID())
        XCTAssertEqual(browser.splitTabIDs, [second.id, first.id])
    }

    func testNavigationHistoryFormInputAndZoomBelongToActivePane() async throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        let left = try XCTUnwrap(browser.activeTab)
        browser.open(page("Left"))
        try await waitUntil { left.pageTitle == "Left" && !left.isLoading }
        _ = try await left.webView?.evaluateJavaScript("document.getElementById('draft').value = 'keep me'")
        browser.startSplitView()
        let right = try XCTUnwrap(browser.activeTab)
        browser.open(page("Right"))
        try await waitUntil { right.pageTitle == "Right" && !right.isLoading }
        browser.open(page("Right2"))
        try await waitUntil { right.pageTitle == "Right2" && right.canGoBack }
        browser.goBack()
        try await waitUntil { right.pageTitle == "Right" && right.canGoForward }
        XCTAssertEqual(left.pageTitle, "Left")
        XCTAssertFalse(left.canGoBack)
        browser.focusOtherSplitPane()
        browser.zoomIn()
        XCTAssertGreaterThan(left.pageZoom, 1)
        XCTAssertEqual(right.pageZoom, 1)
        XCTAssertTrue(browser.suspendableTabs.isEmpty)
        await browser.suspendTabs([left, right])
        XCTAssertFalse(left.isSuspended)
        XCTAssertFalse(right.isSuspended)
        browser.endSplitView()
        XCTAssertEqual(browser.tabs.count, 2)
        let draft = try await left.webView?.evaluateJavaScript("document.getElementById('draft').value") as? String
        XCTAssertEqual(draft, "keep me")
        XCTAssertTrue(right.canGoForward)
    }

    func testJoinedCardMirrorsPaneOrderWithoutReorderingStoredTabs() throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        for _ in 0..<3 { browser.addTab() }
        let original = browser.tabs.map(\.id)
        browser.startSplitView(with: original[0])
        XCTAssertEqual(browser.tabStripGroups.map { $0.tabs.map(\.id) },
                       [[original[3], original[0]], [original[1]], [original[2]]])
        XCTAssertEqual(browser.tabs.map(\.id), original)
        browser.focusOtherSplitPane()
        XCTAssertEqual(browser.tabStripGroups.first?.tabs.map(\.id), [original[3], original[0]])
        browser.endSplitView()
        XCTAssertEqual(browser.tabStripGroups.map { $0.tabs.map(\.id) }, original.map { [$0] })
    }

    func testDraggingEitherMemberMovesJoinedCardAsAUnit() throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        for _ in 0..<3 { browser.addTab() }
        let ids = browser.tabs.map(\.id)
        browser.activeTabID = ids[0]
        browser.startSplitView(with: ids[2])
        browser.moveTabGroup(containing: ids[2], beside: ids[3])
        XCTAssertEqual(browser.tabs.map(\.id), [ids[1], ids[3], ids[0], ids[2]])
        XCTAssertEqual(browser.splitTabIDs, [ids[0], ids[2]])
        browser.moveTabGroup(containing: ids[0], beside: ids[2])
        XCTAssertEqual(browser.tabs.map(\.id), [ids[1], ids[3], ids[0], ids[2]])
        browser.moveTabGroup(containing: ids[1], beside: ids[0])
        XCTAssertEqual(browser.tabs.map(\.id), [ids[3], ids[0], ids[2], ids[1]])
        browser.moveTabGroup(containing: ids[2], beside: ids[3])
        XCTAssertEqual(browser.tabs.map(\.id), [ids[0], ids[2], ids[3], ids[1]])
        XCTAssertEqual(browser.activeTabID, ids[2])
        browser.closeTab(ids[2])
        XCTAssertEqual(browser.tabStripGroups.map { $0.tabs.map(\.id) }, [[ids[0]], [ids[3]], [ids[1]]])
    }

    func testClosingAfterJoinedCardKeepsBothNonAdjacentMembers() throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        for _ in 0..<3 { browser.addTab() }
        let ids = browser.tabs.map(\.id)
        browser.startSplitView(with: ids[0])
        browser.closeTabs(afterGroupContaining: ids[3])
        XCTAssertEqual(browser.tabs.map(\.id), [ids[0], ids[3]])
        XCTAssertEqual(browser.splitTabIDs, [ids[3], ids[0]])
        XCTAssertEqual(browser.activeTabID, ids[0])
        browser.reopenClosedTab()
        XCTAssertEqual(browser.tabs.count, 3)
    }

    func testClosingEitherTabKeepsItsPartnerSelected() throws {
        for closeActive in [true, false] {
            let browser = BrowserModel.makePrivate()
            defer { browser.releaseClosedWindow() }
            browser.addTab() // A third tab must not be chosen instead of the surviving pane.
            let left = try XCTUnwrap(browser.activeTabID)
            browser.startSplitView()
            let right = try XCTUnwrap(browser.activeTabID)
            browser.closeTab(closeActive ? right : left)
            XCTAssertFalse(browser.isSplitView)
            XCTAssertEqual(browser.activeTabID, closeActive ? left : right)
            XCTAssertEqual(browser.tabs.count, 2)
            browser.reopenClosedTab()
            XCTAssertEqual(browser.tabs.count, 3)
        }
    }

    func testBulkCloseAndSessionReplacementLeaveNoDanglingSplit() throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        let first = try XCTUnwrap(browser.activeTabID)
        browser.startSplitView()
        browser.closeTabs(after: first)
        XCTAssertFalse(browser.isSplitView)
        XCTAssertEqual(browser.activeTabID, first)
        browser.startSplitView()
        browser.closeOtherTabs(than: first)
        XCTAssertFalse(browser.isSplitView)
        XCTAssertEqual(browser.tabs.count, 1)
        browser.startSplitView()
        let session = browser.windowSession()
        browser.restoreSession(session)
        XCTAssertFalse(browser.isSplitView)
        XCTAssertEqual(browser.tabs.count, 2)
    }

    func testLeavingSplitAndSelectingAnotherTabPreserveBothViews() throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        let outside = try XCTUnwrap(browser.activeTabID)
        browser.addTab()
        browser.startSplitView()
        let pages = browser.splitTabs
        let views = pages.compactMap(\.webView)
        browser.endSplitView(keeping: pages[0].id)
        XCTAssertEqual(browser.activeTabID, pages[0].id)
        XCTAssertEqual(browser.tabs.count, 3)
        browser.startSplitView(with: pages[1].id)
        browser.activeTabID = outside
        XCTAssertFalse(browser.isSplitView)
        XCTAssertTrue(browser.hasSplitPair)
        XCTAssertEqual(browser.splitTabIDs, pages.map(\.id))
        XCTAssertEqual(browser.tabStripGroups.filter { $0.tabs.count == 2 }.count, 1)
        XCTAssertTrue(pages.allSatisfy { !browser.isTabVisible($0.id) })
        for page in pages {
            browser.activeTabID = page.id
            XCTAssertTrue(browser.isSplitView)
            XCTAssertTrue(pages.allSatisfy { browser.isTabVisible($0.id) })
        }
        XCTAssertEqual(pages.compactMap(\.webView), views)
    }

    func testReturningToParkedPairRestoresBothSuspendedPages() async throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        let left = try XCTUnwrap(browser.activeTab)
        browser.open(page("ParkedLeft"))
        try await waitUntil { left.pageTitle == "ParkedLeft" && !left.isLoading }
        browser.startSplitView()
        let right = try XCTUnwrap(browser.activeTab)
        browser.open(page("ParkedRight"))
        try await waitUntil { right.pageTitle == "ParkedRight" && !right.isLoading }
        browser.addTab()
        let outside = browser.activeTabID
        XCTAssertFalse(browser.isSplitView)
        XCTAssertTrue(browser.hasSplitPair)
        XCTAssertTrue(browser.suspendableTabs.contains { $0 === left })
        XCTAssertTrue(browser.suspendableTabs.contains { $0 === right })
        browser.focusOtherSplitPane()
        XCTAssertEqual(browser.activeTabID, outside)
        await browser.suspendTabs([left, right])
        XCTAssertTrue(left.isSuspended)
        XCTAssertTrue(right.isSuspended)
        browser.activeTabID = right.id
        try await waitUntil { !left.isSuspended && !right.isSuspended && !left.isLoading && !right.isLoading }
        XCTAssertEqual(browser.splitTabIDs, [left.id, right.id])
        XCTAssertTrue(browser.suspendableTabs.isEmpty)
        XCTAssertTrue(browser.isTabVisible(left.id))
    }

    func testClosingOrUngroupingParkedPairDoesNotSelectItsSurvivor() throws {
        for closesTab in [true, false] {
            let browser = BrowserModel.makePrivate()
            defer { browser.releaseClosedWindow() }
            browser.startSplitView()
            let pair = browser.splitTabIDs
            browser.addTab()
            let outside = browser.activeTabID
            if closesTab { browser.closeTab(pair[1]) }
            else { browser.endSplitView() }
            XCTAssertFalse(browser.hasSplitPair)
            XCTAssertEqual(browser.activeTabID, outside)
            browser.activeTabID = pair[0]
            XCTAssertFalse(browser.isSplitView)
        }
    }

    func testPrivateSplitSharesCookiesOnlyWithinItsWindow() async throws {
        let browser = BrowserModel.makePrivate()
        let other = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow(); other.releaseClosedWindow() }
        browser.startSplitView()
        browser.splitTabs.forEach { $0.load(page("Private")) }
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "split.example", .path: "/", .name: "session", .value: "split-only"]))
        let leftStore = try XCTUnwrap(browser.splitTabs.first?.webView?.configuration.websiteDataStore)
        let rightStore = try XCTUnwrap(browser.splitTabs.last?.webView?.configuration.websiteDataStore)
        await leftStore.httpCookieStore.setCookie(cookie)
        let rightCookies = await rightStore.httpCookieStore.allCookies()
        let otherCookies = await other.websiteDataStore.httpCookieStore.allCookies()
        XCTAssertEqual(rightCookies.first(where: { $0.name == "session" })?.value, "split-only")
        XCTAssertTrue(otherCookies.isEmpty)
        XCTAssertFalse(leftStore.isPersistent)
        browser.startSplitView(with: try XCTUnwrap(other.activeTabID))
        XCTAssertEqual(browser.tabs.count, 2)
        XCTAssertTrue(browser.splitTabs.allSatisfy { $0.browser === browser })
    }

    func testKeyboardFocusSelectsTheCorrespondingWebPane() throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        browser.startSplitView()
        let left = browser.splitTabs[0]
        let right = browser.splitTabs[1]
        for tab in [left, right] {
            tab.isNewTab = false
            tab.restore()
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: true)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        window.contentView = container
        container.addSubview(left.contentView)
        container.addSubview(right.contentView)
        XCTAssertTrue(window.makeFirstResponder(left.webView))
        XCTAssertEqual(browser.activeTabID, left.id)
        XCTAssertTrue(window.makeFirstResponder(right.webView))
        XCTAssertEqual(browser.activeTabID, right.id)
    }

    func testNativeHostsKeepPagesAttachedAcrossSplitTransitions() async throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        let first = try XCTUnwrap(browser.activeTab)
        browser.open(page("Attached"))
        try await waitUntil { first.pageTitle == "Attached" && !first.isLoading }
        _ = try await first.webView?.evaluateJavaScript("document.getElementById('draft').value = 'still here'")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = NSHostingView(rootView: SplitHostFixture(browser: browser))
        window.contentView?.layoutSubtreeIfNeeded()
        try await waitUntil { first.webView?.window === window }
        browser.startSplitView()
        let second = try XCTUnwrap(browser.activeTab)
        browser.open(page("Second"))
        try await waitUntil { first.webView?.window === window && second.webView?.window === window }

        try await waitUntil { self.nativeSplit(in: window.contentView)?.arrangedSubviews.count == 2 }
        // Wait until the divider observer has completed the initial restore, then resize natively.
        try await Task.sleep(for: .milliseconds(200))
        let split = try XCTUnwrap(nativeSplit(in: window.contentView))
        split.setPosition(560, ofDividerAt: 0)
        try await waitUntil { browser.splitDividerFraction > 0.6 }
        let fraction = browser.splitDividerFraction
        browser.addTab()
        let outside = try XCTUnwrap(browser.activeTab)
        try await waitUntil { outside.contentView.window === window && first.webView?.window == nil }
        XCTAssertTrue(browser.hasSplitPair)
        browser.activeTabID = first.id
        try await waitUntil { first.webView?.window === window && second.webView?.window === window }
        try await waitUntil {
            guard let restored = self.nativeSplit(in: window.contentView), let leading = restored.arrangedSubviews.first else { return false }
            return abs(leading.frame.width / (restored.bounds.width - restored.dividerThickness) - fraction) < 0.01
        }
        XCTAssertEqual(browser.splitDividerFraction, fraction, accuracy: 0.01)
        browser.endSplitView(keeping: first.id)
        // Allow both removal and insertion in SwiftUI's asynchronous transaction to finish.
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(first.webView?.window === window)
        let draft = try await first.webView?.evaluateJavaScript("document.getElementById('draft').value") as? String
        XCTAssertEqual(draft, "still here")
        browser.startSplitView(with: second.id)
        try await waitUntil { first.webView?.window === window && second.webView?.window === window }
        browser.closeTab(second.id)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(first.webView?.window === window)
        window.contentView = nil
    }

    private func nativeSplit(in view: NSView?) -> NSSplitView? {
        if let split = view as? NSSplitView { return split }
        for child in view?.subviews ?? [] {
            if let split = nativeSplit(in: child) { return split }
        }
        return nil
    }

    func testNonActiveVisiblePaneRecoversFromWebProcessTermination() async throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        let left = try XCTUnwrap(browser.activeTab)
        browser.open(page("Recover"))
        try await waitUntil { left.pageTitle == "Recover" && !left.isLoading }
        browser.startSplitView()
        let webView = try XCTUnwrap(left.webView)
        let delegate = try XCTUnwrap(webView.navigationDelegate)
        delegate.webViewWebContentProcessDidTerminate?(webView)
        try await waitUntil { !left.isLoading && left.pageTitle == "Recover" }
        XCTAssertFalse(left.isSuspended)
        XCTAssertTrue(left.webView === webView)
    }
}

private struct SplitHostFixture: View {
    let browser: BrowserModel

    var body: some View {
        Group {
            if browser.isSplitView {
                HSplitView {
                    ForEach(browser.splitTabs) { tab in
                        PageHost(content: tab.contentView).frame(minWidth: 180)
                            .background {
                                if tab.id == browser.splitTabIDs.first {
                                    SplitDividerPosition(browser: browser)
                                }
                            }
                    }
                }
            } else if let tab = browser.activeTab {
                PageHost(content: tab.contentView)
            }
        }
        .frame(width: 900, height: 600)
    }
}
