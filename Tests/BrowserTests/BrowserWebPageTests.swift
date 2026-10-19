import AppKit
import Observation
import SwiftUI
import WebKit
import XCTest
@testable import Browser

@MainActor
final class BrowserWebPageTests: XCTestCase {
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
            tab.isFindBarVisible.toggle()
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
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
        let draft = try await webView.evaluateJavaScript("document.getElementById('draft').value") as? String
        XCTAssertEqual(draft, "retained draft")
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
