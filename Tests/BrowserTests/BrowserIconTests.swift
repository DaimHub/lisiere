import AppKit
import SwiftUI
import XCTest
@testable import Browser

@MainActor
final class BrowserIconTests: XCTestCase {
    func testSwiftUIIconIdentityIsStableWithoutSharingMutableAppKitImages() {
        let small = Image(browserIcon: .tabGroup, size: 13)
        XCTAssertEqual(small, Image(browserIcon: .tabGroup, size: 13))
        XCTAssertNotEqual(small, Image(browserIcon: .tabGroup, size: 24))
        XCTAssertNotEqual(small, Image(browserIcon: .forward, size: 13))
        let mutable = BrowserIcon.tabGroup.nsImage(size: 13)
        mutable.size = NSSize(width: 40, height: 40)
        mutable.isTemplate = false
        XCTAssertEqual(small, Image(browserIcon: .tabGroup, size: 13))
        XCTAssertTrue(BrowserIcon.tabGroup.nsImage(size: 13).isTemplate)
    }

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

    func testSettingsArtworkKeepsAnInsetWhenAppKitExpandsTheTabImage() throws {
        for icon in [BrowserIcon.settings, .appearance, .privacy, .key, .globe, .downloads, .profiles] {
            let image = icon.settingsTabImage()
            XCTAssertEqual(image.size, NSSize(width: 32, height: 32))
            XCTAssertTrue(image.isTemplate)
            var rect = NSRect(x: 0, y: 0, width: 32, height: 32)
            let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            var ink = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
                    ink += 1
                    XCTAssertGreaterThanOrEqual(Double(x) / Double(bitmap.pixelsWide), 0.12)
                    XCTAssertLessThan(Double(x) / Double(bitmap.pixelsWide), 0.88)
                    XCTAssertGreaterThanOrEqual(Double(y) / Double(bitmap.pixelsHigh), 0.12)
                    XCTAssertLessThan(Double(y) / Double(bitmap.pixelsHigh), 0.88)
                }
            }
            XCTAssertGreaterThan(ink, 0, icon.asset.resourceName)
        }
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

    func testNativeCommandsShowIconsAndKeepASingleSettingsEntry() throws {
        let main = try XCTUnwrap(NSApp.mainMenu)
        func items(in menu: NSMenu) -> [NSMenuItem] {
            menu.update()
            return menu.items.flatMap { item in
                [item] + (item.submenu.map { items(in: $0) } ?? [])
            }
        }
        let commands = items(in: main)
        XCTAssertEqual(commands.filter { $0.title == "Settings…" }.count, 1)
        for title in ["New Window", "New Private Window", "New Tab", "Reload Page", "Manage Profiles…"] {
            let matches = commands.filter { $0.title == title }
            XCTAssertEqual(matches.count, 1, "Duplicate or missing command: \(title)")
            let image = try XCTUnwrap(matches.first?.image, "Missing menu icon: \(title)")
            XCTAssertTrue(image.isValid, title)
            XCTAssertTrue(image.isTemplate, "AppKit must tint \(title) for appearance, selection and disabled state")
            XCTAssertTrue(image.name()?.hasPrefix("Lisiere.Hugeicons.") == true, title)
            if #available(macOS 27.0, *) {
                XCTAssertEqual(matches.first?.value(forKey: "preferredImageVisibility") as? Int, 1, title)
            }
        }
    }

    func testNativeContextMenuPreservesActionsAndDisabledState() throws {
        var invocationCount = 0
        let menu = BrowserContextAction.menu([
            .init(title: "Open", icon: .open) { invocationCount += 1 },
            .separator,
            .init(title: "Reload", icon: .reload, isEnabled: false)
        ])
        XCTAssertFalse(menu.autoenablesItems)
        XCTAssertEqual(menu.items.map(\.title), ["Open", "", "Reload"])
        XCTAssertTrue(menu.items[1].isSeparatorItem)
        XCTAssertTrue(menu.items[0].isEnabled)
        XCTAssertFalse(menu.items[2].isEnabled)
        for item in [menu.items[0], menu.items[2]] {
            XCTAssertTrue(try XCTUnwrap(item.image).isTemplate)
            if #available(macOS 27.0, *) { XCTAssertEqual(item.value(forKey: "preferredImageVisibility") as? Int, 1) }
        }
        menu.performActionForItem(at: 0)
        XCTAssertEqual(invocationCount, 1)
        let parent = BrowserContextAction.menu([
            .init(title: "Profiles", icon: .profiles, children: [
                .init(title: "Profile: Personal", icon: nil, isEnabled: false),
                .init(title: "Personal", icon: .profile)
            ])
        ])
        let submenu = try XCTUnwrap(parent.items.first?.submenu)
        XCTAssertEqual(submenu.items.map(\.title), ["Profile: Personal", "Personal"])
        XCTAssertFalse(submenu.items[0].isEnabled)
        XCTAssertNil(submenu.items[0].image)
        XCTAssertTrue(try XCTUnwrap(submenu.items[1].image).isTemplate)
    }

    func testHugeiconsLicenseTravelsWithTheApp() throws {
        let file = try XCTUnwrap(Bundle.main.url(forResource: "LICENSE-hugeicons", withExtension: "txt"))
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.contains("Copyright (c) 2025 Hugeicons"))
        XCTAssertTrue(text.contains("Copyright (c) 2026 Ivan Sapozhnik"))
    }
}
