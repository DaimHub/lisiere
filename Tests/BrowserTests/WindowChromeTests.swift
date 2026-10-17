import AppKit
import XCTest
@testable import Browser

@MainActor
final class WindowChromeTests: XCTestCase {
    func testWindowButtonsStayCenteredAfterLayoutSwitchesAndResize() async throws {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        let chrome = WindowChromeView(frame: window.contentView!.bounds)
        chrome.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(chrome)
        defer { window.close() }

        for height in [46.0, 40.0, 46.0, 40.0, 46.0] {
            chrome.titlebarHeight = height
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
            assertButtons(window, height: height)
            window.setContentSize(NSSize(width: window.frame.width + 10, height: window.frame.height + 10))
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
            assertButtons(window, height: height)
            // AppKit may restore its default inner titlebar while replacing hosted profile content,
            // without posting an NSWindow resize notification or changing our requested row height.
            let titlebar = try XCTUnwrap(window.standardWindowButton(.closeButton)?.superview)
            titlebar.setFrameSize(NSSize(width: titlebar.frame.width, height: 22))
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                let button = try XCTUnwrap(window.standardWindowButton(type))
                button.setFrameOrigin(NSPoint(x: button.frame.minX, y: (22 - button.frame.height) / 2))
            }
            try await Task.sleep(for: .milliseconds(30))
            assertButtons(window, height: height)
            // A standard-control refresh can also move the buttons without resizing either titlebar view.
            window.standardWindowButton(.closeButton)?.setFrameOrigin(NSPoint(x: 6, y: 3))
            try await Task.sleep(for: .milliseconds(30))
            assertButtons(window, height: height)
        }
    }

    private func assertButtons(_ window: NSWindow, height: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        for (index, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let button = window.standardWindowButton(type) else { return XCTFail("Missing window control") }
            let frame = button.convert(button.bounds, to: nil)
            XCTAssertEqual(window.frame.height - frame.midY, height / 2, accuracy: 0.5, file: file, line: line)
            XCTAssertEqual(frame.minX, BrowserChrome.windowButtonLeading(titlebarHeight: height)
                           + CGFloat(index) * BrowserChrome.windowButtonSpacing, accuracy: 0.5, file: file, line: line)
        }
    }
}
