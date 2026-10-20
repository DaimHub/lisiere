import AppKit
import SwiftUI
import XCTest
@testable import Browser

@MainActor
final class ProfileDeckTests: XCTestCase {
    func testWarmPresentationRetainsSurfacesAndDoesNotRestartTheFadeDuringModelUpdates() async throws {
        let a = UUID(), b = UUID()
        let items = [ProfileDeckItem(id: a, content: Color.blue), ProfileDeckItem(id: b, content: Color.red)]
        let deck = ProfileDeckView<Color>(frame: .zero)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = deck
        deck.update(items: items, activeID: a, animated: true)
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(40))
        let first = try XCTUnwrap(deck.surfaces[a])
        let second = try XCTUnwrap(deck.surfaces[b])
        XCTAssertNil(first.opacityLayer.animation(forKey: "profile-fade"), "The first presentation is immediate")
        XCTAssertFalse(deck.beginTransition(to: UUID()), "An unrendered profile uses the normal creation path")

        XCTAssertTrue(deck.beginTransition(to: b))
        XCTAssertEqual(deck.activeID, b)
        XCTAssertFalse(first.isActive)
        XCTAssertNil(first.hitTest(NSPoint(x: 50, y: 50)))
        XCTAssertTrue(first.isAccessibilityHidden())
        XCTAssertTrue(second.isActive)
        XCTAssertFalse(second.isAccessibilityHidden())
        XCTAssertGreaterThan(second.layer!.zPosition, first.layer!.zPosition)
        let fade = try XCTUnwrap(second.opacityLayer.animation(forKey: "profile-fade") as? CABasicAnimation)
        XCTAssertEqual(fade.duration, 0.22)
        XCTAssertEqual(fade.preferredFrameRateRange.preferred, Float(window.screen?.maximumFramesPerSecond ?? 60))
        try await Task.sleep(for: .milliseconds(80))
        let middle = try XCTUnwrap(second.opacityLayer.presentation()?.opacity)
        XCTAssertGreaterThan(middle, 0)
        XCTAssertLessThan(middle, 1)

        deck.update(items: items, activeID: b, animated: true)
        XCTAssertTrue(deck.surfaces[a] === first)
        XCTAssertTrue(deck.surfaces[b] === second)
        let continued = try XCTUnwrap(second.opacityLayer.animation(forKey: "profile-fade") as? CABasicAnimation)
        XCTAssertEqual(try XCTUnwrap(continued.fromValue as? Float), 0,
                       "The SwiftUI update must not restart a fade already submitted by the controller")
        let reversingFrom = try XCTUnwrap(first.opacityLayer.presentation()?.opacity)
        XCTAssertTrue(deck.beginTransition(to: a))
        let reversed = try XCTUnwrap(first.opacityLayer.animation(forKey: "profile-fade") as? CABasicAnimation)
        XCTAssertEqual(try XCTUnwrap(reversed.fromValue as? Float), reversingFrom, accuracy: 0.1)

        deck.update(items: items, activeID: a, animated: false)
        XCTAssertNil(first.opacityLayer.animation(forKey: "profile-fade"))
        XCTAssertEqual(first.opacityLayer.opacity, 1)
        XCTAssertTrue(deck.beginTransition(to: b))
        XCTAssertNil(second.opacityLayer.animation(forKey: "profile-fade"))
        XCTAssertEqual(second.opacityLayer.opacity, 1)
        deck.update(items: [items[1]], activeID: b, animated: false)
        XCTAssertEqual(deck.surfaces.count, 1)
        XCTAssertNil(first.superview)
        deck.releaseSurfaces()
        XCTAssertTrue(deck.surfaces.isEmpty)
        XCTAssertNil(deck.activeID)
        XCTAssertNil(second.superview)
    }
}
