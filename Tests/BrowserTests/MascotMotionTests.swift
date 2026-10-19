import AppKit
import XCTest
@testable import Browser

@MainActor
final class MascotMotionTests: XCTestCase {
    func testNativeMotionStopsForReducedMotionAndRestartsAfterReattachment() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let view = MascotArtworkView(frame: NSRect(x: 0, y: 0, width: 120, height: 120))
        defer { window.contentView = nil }
        view.update(mascot: .lutin, palette: .black, gaze: .zero, animated: true)
        XCTAssertNil(view.movingLayer.animation(forKey: "bob"), "Detached artwork must not animate")
        window.contentView = view
        XCTAssertNotNil(view.movingLayer.animation(forKey: "bob"))
        XCTAssertNotNil(view.eyeLayer.animation(forKey: "blink"))
        view.update(mascot: .lutin, palette: .white, gaze: .zero, animated: false)
        XCTAssertNil(view.movingLayer.animation(forKey: "bob"))
        XCTAssertNil(view.eyeLayer.animation(forKey: "blink"))
        XCTAssertTrue(CATransform3DIsIdentity(view.movingLayer.transform))
        XCTAssertTrue(CATransform3DIsIdentity(view.eyeLayer.transform))
        view.update(mascot: .lutin, palette: .white, gaze: CGSize(width: 3, height: 2), animated: true)
        XCTAssertNotNil(view.movingLayer.animation(forKey: "bob"))
        window.contentView = nil
        XCTAssertNil(view.movingLayer.animation(forKey: "bob"))
        window.contentView = view
        XCTAssertNotNil(view.eyeLayer.animation(forKey: "blink"))
        XCTAssertNil(view.layer?.backgroundColor, "The start-page artwork must remain transparent")
        XCTAssertNil(view.hitTest(CGPoint(x: 60, y: 60)))
    }
}
