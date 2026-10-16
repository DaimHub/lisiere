import AppKit
import XCTest
@testable import Browser

@MainActor
final class BrowserIconTests: XCTestCase {
    func testEveryInterfaceIconIsBundledAndRendersPixels() throws {
        for icon in BrowserIcon.allCases {
            let original = try XCTUnwrap(icon.asset.nsImage(), "Missing \(icon.asset.resourceName)")
            XCTAssertTrue(original.isValid, icon.asset.resourceName)
            let image = icon.nsImage(size: 20)
            XCTAssertTrue(image.isTemplate)
            var rect = NSRect(x: 0, y: 0, width: 20, height: 20)
            let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            let hasInk = (0..<bitmap.pixelsHigh).contains { y in
                (0..<bitmap.pixelsWide).contains { x in
                    (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1
                }
            }
            XCTAssertTrue(hasInk, "Empty icon: \(icon.asset.resourceName)")
        }
    }

    func testSizingOneControlDoesNotResizeOtherControlsOrPackageAssets() throws {
        let original = try XCTUnwrap(BrowserIcon.search.asset.nsImage())
        let originalSize = original.size
        let small = BrowserIcon.search.nsImage(size: 11, accessibilityDescription: "Search")
        let large = BrowserIcon.search.nsImage(size: 34)
        XCTAssertEqual(small.size, NSSize(width: 11, height: 11))
        XCTAssertEqual(large.size, NSSize(width: 34, height: 34))
        XCTAssertEqual(original.size, originalSize)
        XCTAssertEqual(small.accessibilityDescription, "Search")
        XCTAssertNil(large.accessibilityDescription)
    }

    func testExistingProfileIconPayloadsRemainCompatible() throws {
        let identifiers = ["person.crop.circle", "briefcase", "house", "book", "globe",
                           "chevron.left.forwardslash.chevron.right", "leaf", "star", "heart",
                           "gamecontroller", "graduationcap", "flask"]
        for identifier in identifiers {
            let data = Data("\"\(identifier)\"".utf8)
            let icon = try JSONDecoder().decode(ProfileIcon.self, from: data)
            XCTAssertEqual(try JSONEncoder().encode(icon), data)
            XCTAssertNotNil(icon.browserIcon.asset.nsImage())
        }
    }

    func testStateIconsRemainVisuallyDistinct() throws {
        for (first, second) in [(BrowserIcon.bookmark, BrowserIcon.bookmarkSelected),
                                (.shield, .shieldOff), (.view, .viewOff),
                                (.reload, .close), (.circle, .checkmarkCircle)] {
            XCTAssertNotEqual(try XCTUnwrap(first.nsImage().tiffRepresentation),
                              try XCTUnwrap(second.nsImage().tiffRepresentation))
        }
    }

    func testHugeiconsLicenseTravelsWithTheApp() throws {
        let file = try XCTUnwrap(Bundle.main.url(forResource: "LICENSE-hugeicons", withExtension: "txt"))
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.contains("Copyright (c) 2025 Hugeicons"))
        XCTAssertTrue(text.contains("Copyright (c) 2026 Ivan Sapozhnik"))
    }
}
