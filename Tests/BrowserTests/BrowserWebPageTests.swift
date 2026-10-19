import AppKit
import Observation
import SwiftUI
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
