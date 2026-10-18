import AppKit
import SwiftUI
import XCTest
@testable import Browser

@MainActor
final class BrowserContextMenuTests: XCTestCase {
    func testHiddenMenuDoesNotBuildActionsDuringRepeatedNativeLayoutUpdates() async throws {
        let calls = MenuBuildCounter()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 240, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: MenuLayoutProbe(width: 100, calls: calls))
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(100))
        let initial = calls.count
        for width in 100..<120 {
            host.rootView = MenuLayoutProbe(width: CGFloat(width), calls: calls)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(calls.count, initial, "Closed menus must not rebuild actions on each layout update")
    }
}

@MainActor
private final class MenuBuildCounter { var count = 0 }

private struct MenuLayoutProbe: View {
    let width: CGFloat
    let calls: MenuBuildCounter
    var body: some View {
        Color.clear.frame(width: width, height: 32).browserContextMenu {
            calls.count += 1
            return [.init(title: "New Tab", icon: .add)]
        }
    }
}
