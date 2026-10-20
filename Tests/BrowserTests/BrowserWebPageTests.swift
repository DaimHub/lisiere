import AppKit
import Observation
import SwiftUI
import WebKit
import XCTest
@testable import Browser

@MainActor
final class BrowserWebPageTests: XCTestCase {
    func testPreparingWorkspaceUnparksOnlyItsVisiblePanesWithoutActivatingOrCreatingWebViews() throws {
        let browser = BrowserModel.makePrivate()
        let first = try XCTUnwrap(browser.activeTab)
        browser.addTab()
        let second = try XCTUnwrap(browser.activeTab)
        browser.addTab()
        let background = try XCTUnwrap(browser.activeTab)
        browser.activeTabID = first.id
        browser.startSplitView(with: second.id)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let root = NSView(frame: window.contentView!.bounds)
        window.contentView = root
        defer { window.contentView = nil; browser.releaseClosedWindow() }
        let hosts = [first, second, background].map { tab in
            let host = PageHostView(frame: root.bounds)
            root.addSubview(host)
            host.show(tab.contentView, tab: tab, browser: browser)
            host.setWorkspaceActive(false, animated: false)
            return host
        }
        browser.setWorkspaceActive(false)
        XCTAssertTrue([first, second, background].allSatisfy { $0.contentView.isHidden })
        browser.prepareWorkspacePresentation()
        XCTAssertFalse(first.contentView.isHidden)
        XCTAssertFalse(second.contentView.isHidden)
        XCTAssertTrue(background.contentView.isHidden)
        XCTAssertFalse(browser.isActiveInWorkspace)
        XCTAssertTrue(browser.tabs.allSatisfy { $0.webView == nil })
        XCTAssertTrue(first.contentView.superview === hosts[0])
        XCTAssertTrue(second.contentView.superview === hosts[1])
    }

    func testFindUpdatesPreserveNativePageAndUnsubmittedForm() async throws {
        let browser = BrowserModel.makePrivate()
        let tab = try XCTUnwrap(browser.activeTab)
        browser.open(URL(string: "data:text/html,<title>Motion</title><input id='draft'>")!)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: BrowserWebPage(tab: tab, browser: browser, accent: .blue, updateAddress: { _ in }))
        window.contentView = host
        defer { window.contentView = nil; browser.releaseClosedWindow() }
        let deadline = ContinuousClock.now + .seconds(10)
        while tab.isLoading || tab.webView?.title != "Motion" || tab.contentView.window !== window {
            guard ContinuousClock.now < deadline else { return XCTFail("Native page did not attach/load") }
            try await Task.sleep(for: .milliseconds(20))
        }
        let webView = try XCTUnwrap(tab.webView)
        let pageHost = try XCTUnwrap(tab.contentView.superview)
        _ = try await webView.evaluateJavaScript("document.getElementById('draft').value = 'unsent draft'")
        for _ in 0..<8 {
            browser.showFindBar()
            try await waitUntil {
                self.descendants(host, of: NSTextField.self).contains { $0.currentEditor() != nil }
            }
            browser.closeFindBar()
            host.layoutSubtreeIfNeeded()
            try await waitUntil { window.firstResponder === webView }
            XCTAssertTrue(descendants(host, of: NSTextField.self).allSatisfy { $0.currentEditor() == nil })
            XCTAssertTrue(tab.webView === webView)
            XCTAssertTrue(tab.contentView.superview === pageHost)
            XCTAssertTrue(webView.window === window)
        }
        let draft = try await webView.evaluateJavaScript("document.getElementById('draft').value") as? String
        XCTAssertEqual(draft, "unsent draft")
    }

    func testSwitchingHomeAndWebRetainsThePageHostAndPausesHiddenMascot() async throws {
        let storeID = UUID()
        let preferences = ProfilePreferences()
        preferences.showsMascot = true
        let browser = BrowserModel(websiteDataStore: WKWebsiteDataStore(forIdentifier: storeID), preferences: preferences)
        let home = try XCTUnwrap(browser.activeTab)
        let bookmarks = BookmarkStore(defaults: nil)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: PageSelection(browser: browser, bookmarks: bookmarks)
            .environment(\.scenePhase, .active))
        host.sizingOptions = []
        window.contentView = host
        defer { window.contentView = nil; browser.releaseClosedWindow() }
        try await waitUntil { self.descendants(host, of: MascotArtworkView.self).count == 1 }
        let mascot = try XCTUnwrap(descendants(host, of: MascotArtworkView.self).first)
        let pageHost = try XCTUnwrap(descendants(host, of: PageHostView.self).first)
        browser.open(URL(string: "data:text/html,<title>Retained</title><input id='draft'>")!, inNewTab: true)
        let page = try XCTUnwrap(browser.activeTab)
        try await waitUntil { !page.isLoading && page.webView?.title == "Retained" && page.contentView.superview === pageHost }
        let webView = try XCTUnwrap(page.webView)
        _ = try await webView.evaluateJavaScript("document.getElementById('draft').value = 'retained draft'")
        for _ in 0..<3 {
            XCTAssertTrue(descendants(host, of: MascotArtworkView.self).first === mascot)
            XCTAssertNil(mascot.movingLayer.animation(forKey: "bob"), "Hidden start-page artwork must stop animating")
            browser.activeTabID = home.id
            try await waitUntil { mascot.movingLayer.animation(forKey: "bob") != nil }
            XCTAssertTrue(descendants(host, of: PageHostView.self).first === pageHost)
            browser.activeTabID = page.id
            try await waitUntil { page.contentView.superview === pageHost && mascot.movingLayer.animation(forKey: "bob") == nil }
            XCTAssertTrue(page.webView === webView)
        }
        browser.open(URL(string: "data:text/html,<title>Other</title><input id='draft'>")!, inNewTab: true)
        let otherPage = try XCTUnwrap(browser.activeTab)
        try await waitUntil { !otherPage.isLoading && otherPage.webView?.title == "Other" && otherPage.contentView.superview === pageHost }
        let otherWebView = try XCTUnwrap(otherPage.webView)
        _ = try await otherWebView.evaluateJavaScript("document.getElementById('draft').value = 'other draft'")
        for selected in [page, otherPage, page, otherPage] {
            browser.activeTabID = selected.id
            try await waitUntil { selected.contentView.superview === pageHost && !selected.contentView.isHidden }
            XCTAssertTrue(descendants(host, of: MascotArtworkView.self).first === mascot)
            XCTAssertNil(mascot.movingLayer.animation(forKey: "bob"))
        }
        let otherDraft = try await otherWebView.evaluateJavaScript("document.getElementById('draft').value") as? String
        XCTAssertEqual(otherDraft, "other draft")
        browser.activeTabID = home.id
        try await waitUntil { mascot.movingLayer.animation(forKey: "bob") != nil }
        browser.setWorkspaceActive(false)
        try await waitUntil { mascot.movingLayer.animation(forKey: "bob") == nil }
        browser.setWorkspaceActive(true)
        try await waitUntil { mascot.movingLayer.animation(forKey: "bob") != nil }
        let draft = try await webView.evaluateJavaScript("document.getElementById('draft').value") as? String
        XCTAssertEqual(draft, "retained draft")
    }

    func testFindFieldFollowsTheSelectedTabWithoutLeakingItsQuery() async throws {
        let browser = BrowserModel.makePrivate()
        let bookmarks = BookmarkStore(defaults: nil)
        browser.open(URL(string: "data:text/html,<title>First</title>first")!)
        let first = try XCTUnwrap(browser.activeTab)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: PageSelection(browser: browser, bookmarks: bookmarks))
        window.contentView = host
        defer { window.contentView = nil; browser.releaseClosedWindow() }
        try await waitUntil { first.contentView.window === window && !first.isLoading }
        browser.showFindBar()
        first.findText = "first"
        try await waitUntil {
            self.descendants(host, of: NSTextField.self).contains { $0.stringValue == "first" && $0.currentEditor() != nil }
        }
        browser.open(URL(string: "data:text/html,<title>Second</title>second")!, inNewTab: true)
        let second = try XCTUnwrap(browser.activeTab)
        try await waitUntil { second.contentView.window === window && !second.isLoading }
        XCTAssertFalse(second.isFindBarVisible)
        XCTAssertEqual(second.findText, "")
        browser.showFindBar()
        second.findText = "second"
        try await waitUntil {
            self.descendants(host, of: NSTextField.self).contains { $0.stringValue == "second" && $0.currentEditor() != nil }
        }
        XCTAssertEqual(first.findText, "first")
        browser.activeTabID = first.id
        try await waitUntil {
            self.descendants(host, of: NSTextField.self).contains { $0.stringValue == "first" }
        }
        browser.closeFindBar()
        try await waitUntil { window.firstResponder === first.webView }
        browser.setWorkspaceActive(false)
        browser.findFocusRequest += 1
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(descendants(host, of: NSTextField.self).allSatisfy { $0.currentEditor() == nil })
    }

    func testHiddenStartPageDoesNotKeepAClosedWebTabAlive() async throws {
        let browser = BrowserModel.makePrivate()
        let bookmarks = BookmarkStore(defaults: nil)
        browser.open(URL(string: "data:text/html,<title>First</title>")!)
        weak var first = browser.activeTab
        let firstID = try XCTUnwrap(first?.id)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: PageSelection(browser: browser, bookmarks: bookmarks))
        window.contentView = host
        defer { window.contentView = nil; browser.releaseClosedWindow() }
        try await waitUntil { first?.contentView.window === window && first?.isLoading == false }
        for title in ["Second", "Third"] {
            browser.open(URL(string: "data:text/html,<title>\(title)</title>")!, inNewTab: true)
            try await waitUntil { browser.activeTab?.pageTitle == title && browser.activeTab?.contentView.window === window }
        }
        browser.closeTab(firstID)
        try await waitUntil { first == nil }
    }

    func testHomeCommandOverridesBlankPreferenceAndSurvivesWorkspaceRoundTrip() async throws {
        let preferences = ProfilePreferences()
        preferences.newTabPage = .blank
        preferences.showsMascot = true
        let browser = BrowserModel(websiteDataStore: WKWebsiteDataStore(forIdentifier: UUID()), preferences: preferences)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: PageSelection(browser: browser, bookmarks: BookmarkStore(defaults: nil)))
        window.contentView = host
        defer { window.contentView = nil; browser.releaseClosedWindow() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(descendants(host, of: MascotArtworkView.self).isEmpty)
        browser.goHome()
        try await waitUntil { self.descendants(host, of: MascotArtworkView.self).count == 1 }
        let mascot = try XCTUnwrap(descendants(host, of: MascotArtworkView.self).first)
        browser.setWorkspaceActive(false)
        try await Task.sleep(for: .milliseconds(40))
        browser.setWorkspaceActive(true)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(descendants(host, of: MascotArtworkView.self).first === mascot)
        XCTAssertNil(browser.activeTab?.webView)
    }

    func testPageHostKeepsOnlyTwoPagesAndStillAllowsSuspensionAndTransfer() async throws {
        let browser = BrowserModel.makePrivate()
        let destination = BrowserModel(websiteDataStore: browser.websiteDataStore)
        let first = try XCTUnwrap(browser.activeTab)
        browser.addTab()
        let second = try XCTUnwrap(browser.activeTab)
        browser.addTab()
        let third = try XCTUnwrap(browser.activeTab)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let host = PageHostView()
        window.contentView = host
        defer { host.releaseContent(); window.contentView = nil; browser.releaseClosedWindow(); destination.releaseClosedWindow() }
        let firstView = first.contentView
        let secondView = second.contentView
        host.show(firstView, tab: first, browser: browser)
        first.isNewTab = false
        second.isNewTab = false
        first.restore()
        second.restore()
        window.makeFirstResponder(first.webView)
        host.show(secondView, tab: second, browser: browser)
        XCTAssertTrue((window.firstResponder as? NSView)?.isDescendant(of: secondView) == true,
                      "Keyboard input must follow the visible cached page")
        XCTAssertTrue(firstView.superview === host)
        XCTAssertTrue(firstView.isHidden)
        XCTAssertFalse(secondView.isHidden)
        host.show(firstView, tab: first, browser: browser)
        XCTAssertEqual(host.subviews.count, 2)
        XCTAssertFalse(firstView.isHidden)
        XCTAssertTrue(secondView.isHidden)
        host.show(third.contentView, tab: third, browser: browser)
        XCTAssertEqual(host.subviews.count, 2)
        XCTAssertNil(secondView.superview, "Only the current page and its immediate predecessor may stay attached")
        first.isNewTab = false
        weak var unloadedWebView: WKWebView?
        autoreleasepool { unloadedWebView = first.webView }
        first.suspend()
        XCTAssertTrue(firstView.subviews.isEmpty, "The cached wrapper must release WebKit when suspended")
        try await waitUntil { unloadedWebView == nil }
        XCTAssertTrue(first.isSuspended)
        let thirdView = third.contentView
        XCTAssertTrue(browser.moveTab(third.id, to: destination))
        let otherWindow = NSWindow(contentRect: window.frame, styleMask: [.titled], backing: .buffered, defer: false)
        let other = PageHostView()
        otherWindow.contentView = other
        defer { other.releaseContent(); otherWindow.contentView = nil }
        other.show(thirdView, tab: third, browser: destination)
        host.releaseContent()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(thirdView.superview === other)
        XCTAssertFalse(thirdView.isHidden)
    }

    func testSwitchingFocusedPageDoesNotSearchTheWindowKeyViewLoop() throws {
        let browser = BrowserModel.makePrivate()
        let first = try XCTUnwrap(browser.activeTab)
        browser.addTab()
        let second = try XCTUnwrap(browser.activeTab)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let host = PageHostView()
        let focused = KeyViewSearchProbe()
        window.contentView = host
        defer { host.releaseContent(); window.contentView = nil; browser.releaseClosedWindow() }
        host.show(focused, tab: first, browser: browser)
        XCTAssertTrue(window.makeFirstResponder(focused))
        focused.isHidden = true
        XCTAssertGreaterThan(focused.searches, 0, "Control: AppKit searches when focus is hidden without first relinquishing it")
        focused.isHidden = false
        XCTAssertTrue(window.makeFirstResponder(focused))
        focused.searches = 0
        host.show(second.contentView, tab: second, browser: browser)
        XCTAssertTrue(focused.isHidden)
        XCTAssertFalse(window.firstResponder === focused)
        XCTAssertEqual(focused.searches, 0, "Hiding a focused page must not trigger SwiftUI's full key-view search")
    }

    func testParkedPageHidesAfterFadeAndRapidReturnCancelsHiding() async throws {
        let browser = BrowserModel.makePrivate()
        let tab = try XCTUnwrap(browser.activeTab)
        tab.isNewTab = false
        tab.restore()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let host = PageHostView()
        window.contentView = host
        defer { host.releaseContent(); window.contentView = nil; browser.releaseClosedWindow() }
        host.show(tab.contentView, tab: tab, browser: browser)
        host.setWorkspaceActive(false, animated: true)
        XCTAssertFalse(tab.contentView.isHidden, "The live page must remain visible throughout the profile fade")
        try await Task.sleep(for: .milliseconds(100))
        host.setWorkspaceActive(true, animated: true)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(tab.contentView.isHidden, "A stale fade completion must never hide the reactivated page")
        browser.setWorkspaceActive(false)
        host.setWorkspaceActive(false, animated: true)
        try await waitUntil { tab.contentView.isHidden }
        XCTAssertTrue(tab.webView?.isHiddenOrHasHiddenAncestor == true)
        host.show(tab.contentView, tab: tab, browser: browser)
        XCTAssertTrue(tab.contentView.isHidden, "A background page update must not unpark its native content")
        window.makeFirstResponder(tab.webView)
        XCTAssertFalse(window.firstResponder === tab.webView, "A parked page cannot steal keyboard focus")
        browser.setWorkspaceActive(true)
        tab.focusPage()
        XCTAssertFalse(tab.contentView.isHidden)
        XCTAssertTrue(window.firstResponder === tab.webView)
        host.setWorkspaceActive(false, animated: false)
        XCTAssertTrue(tab.contentView.isHidden, "Reduce Motion must park the page immediately")
        host.setWorkspaceActive(true, animated: false)
        XCTAssertFalse(tab.contentView.isHidden)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            guard ContinuousClock.now < deadline else { return XCTFail("Native view did not reach expected state") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, of: type) }
    }

    func testPageShellDoesNotObserveFindState() throws {
        let browser = BrowserModel.makePrivate()
        defer { browser.releaseClosedWindow() }
        let tab = try XCTUnwrap(browser.activeTab)
        let changes = ChangeFlag()
        withObservationTracking {
            _ = BrowserWebPage(tab: tab, browser: browser, accent: .blue, updateAddress: { _ in }).body
        } onChange: { changes.value = true }
        tab.isFindBarVisible.toggle()
        // Transient overlay changes must not reconstruct the native page host or surrounding chrome.
        XCTAssertFalse(changes.value)
    }
}

private final class KeyViewSearchProbe: NSView {
    var searches = 0
    override var acceptsFirstResponder: Bool { true }
    override var nextValidKeyView: NSView? {
        searches += 1
        return super.nextValidKeyView
    }
}

private final class ChangeFlag: @unchecked Sendable {
    var value = false
}

private struct PageSelection: View {
    let browser: BrowserModel
    let bookmarks: BookmarkStore
    var body: some View {
        if let tab = browser.activeTab {
            BrowserPage(bookmarks: bookmarks, browser: browser, tab: tab, accent: .blue,
                        focusAddress: {}, updateAddress: { _ in })
        }
    }
}
