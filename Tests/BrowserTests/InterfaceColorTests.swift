import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import Browser

@MainActor
final class InterfaceColorTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "InterfaceColorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testMissingOrInvalidPreferencesPreserveTheOriginalAppearance() {
        let defaults = defaults()
        for value in [nil, "future-palette"] as [String?] {
            defaults.set(value, forKey: BrowserInterfaceColor.storageKey)
            defaults.set("not-a-color", forKey: BrowserInterfaceColor.customStorageKey)
            let store = AppearanceStore(defaults: defaults, applyAppearance: { _ in })
            XCTAssertEqual(store.interfaceColor, .original)
            XCTAssertEqual(BrowserInterfaceColor.hex(for: store.customInterfaceColor), BrowserInterfaceColor.defaultCustomHex)
            XCTAssertNil(store.interfaceColor.tint(for: .light, customColor: store.customInterfaceColor))
            XCTAssertNil(store.interfaceColor.tint(for: .dark, customColor: store.customInterfaceColor))
        }
    }

    func testPaletteAndCustomColorSurviveRelaunchAndResetIndependently() {
        let defaults = defaults()
        let store = AppearanceStore(defaults: defaults, applyAppearance: { _ in })
        store.customInterfaceColor = NSColor(srgbRed: 1, green: 0, blue: 0.5, alpha: 0.2)
        for choice in BrowserInterfaceColor.allCases {
            store.interfaceColor = choice
            let restored = AppearanceStore(defaults: defaults, applyAppearance: { _ in })
            XCTAssertEqual(restored.interfaceColor, choice)
            XCTAssertEqual(BrowserInterfaceColor.hex(for: restored.customInterfaceColor), "FF0080")
            XCTAssertEqual(restored.customInterfaceColor.alphaComponent, 1)
        }
        store.interfaceColor = .original
        store.interfaceColor = .custom
        XCTAssertEqual(BrowserInterfaceColor.hex(for: store.customInterfaceColor), "FF0080")
    }

    func testInterfaceColorDoesNotChangeAppOrWebsiteAppearance() {
        let defaults = defaults()
        var appliedCount = 0
        let store = AppearanceStore(defaults: defaults, applyAppearance: { _ in appliedCount += 1 })
        store.selection = .light
        store.pageSelection = .dark
        let webView = WKWebView()
        store.attach(webView)
        let countBefore = appliedCount
        for choice in BrowserInterfaceColor.allCases {
            store.interfaceColor = choice
            store.customInterfaceColor = .red
            XCTAssertEqual(store.selection, .light)
            XCTAssertEqual(store.pageSelection, .dark)
            XCTAssertEqual(webView.appearance?.name, .darkAqua)
        }
        XCTAssertEqual(appliedCount, countBefore)
    }

    func testCustomColorsStayReadableEvenWithExtremeColorsBehindGlass() throws {
        let seeds: [NSColor] = [.black, .white] + (0..<24).map {
            NSColor(calibratedHue: CGFloat($0) / 24, saturation: 1, brightness: 1, alpha: 1)
        }
        for scheme in [ColorScheme.light, .dark] {
            for seed in seeds {
                let tint = try XCTUnwrap(BrowserInterfaceColor.custom.tint(for: scheme, customColor: seed)?.usingColorSpace(.sRGB))
                for backdrop: CGFloat in [0, 1] {
                    let surface = [tint.redComponent, tint.greenComponent, tint.blueComponent].map {
                        $0 * tint.alphaComponent + backdrop * (1 - tint.alphaComponent)
                    }
                    // Match native primary text's translucent white in dark mode and black in light mode.
                    let text = surface.map { scheme == .dark ? 0.85 + $0 * 0.15 : $0 * 0.15 }
                    let a = luminance(surface)
                    let b = luminance(text)
                    let contrast = (max(a, b) + 0.05) / (min(a, b) + 0.05)
                    XCTAssertGreaterThanOrEqual(contrast, 4.5, "\(scheme), seed \(seed), backdrop \(backdrop)")
                }
            }
        }
    }

    func testProfileColorsAndMascotVisibilityPersistCopyAndStayIndependent() throws {
        let defaults = defaults()
        let root = FileManager.default.temporaryDirectory.appending(path: "InterfaceProfiles-\(UUID())")
        let profiles = ProfileStore(root: root, defaults: defaults)
        defer {
            for profile in profiles.profiles where !profile.isInitial {
                defaults.removePersistentDomain(forName: ProfileStore.defaultsDomain(for: profile.id))
            }
            try? FileManager.default.removeItem(at: root)
        }
        let personal = try XCTUnwrap(profiles.context(for: BrowserProfile.initialID)).preferences
        let work = try profiles.create(name: "Work")
        let preferences = try XCTUnwrap(profiles.context(for: work.id)).preferences
        let toolbarBefore = preferences.toolbarLayout.storedValue
        let accentBefore = preferences.resolvedAccent
        preferences.appearance.interfaceColor = .custom
        preferences.appearance.customInterfaceColor = .red
        preferences.showsMascot = false
        personal.appearance.interfaceColor = .ocean
        XCTAssertTrue(personal.showsMascot)
        XCTAssertEqual(preferences.toolbarLayout.storedValue, toolbarBefore)
        XCTAssertEqual(preferences.resolvedAccent, accentBefore)

        let reopened = ProfileStore(root: root, defaults: defaults)
        let restored = try XCTUnwrap(reopened.context(for: work.id)).preferences
        XCTAssertEqual(restored.appearance.interfaceColor, .custom)
        XCTAssertEqual(BrowserInterfaceColor.hex(for: restored.appearance.customInterfaceColor), "FF0000")
        XCTAssertFalse(restored.showsMascot)
        let copiedProfile = try profiles.create(name: "Copy", copying: work.id)
        let copied = try XCTUnwrap(profiles.context(for: copiedProfile.id)).preferences
        XCTAssertEqual(copied.appearance.interfaceColor, .custom)
        XCTAssertEqual(BrowserInterfaceColor.hex(for: copied.appearance.customInterfaceColor), "FF0000")
        XCTAssertFalse(copied.showsMascot)
        copied.appearance.interfaceColor = .sand
        copied.appearance.customInterfaceColor = .blue
        copied.showsMascot = true
        XCTAssertEqual(preferences.appearance.interfaceColor, .custom)
        XCTAssertEqual(BrowserInterfaceColor.hex(for: preferences.appearance.customInterfaceColor), "FF0000")
        XCTAssertEqual(personal.appearance.interfaceColor, .ocean)
        XCTAssertFalse(preferences.showsMascot)
    }

    func testTemporaryProfileKeepsItsColorChangesEphemeral() {
        let first = ProfilePreferences()
        first.appearance.interfaceColor = .custom
        first.appearance.customInterfaceColor = .red
        first.showsMascot = false
        let next = ProfilePreferences()
        XCTAssertNil(first.defaults)
        XCTAssertEqual(next.appearance.interfaceColor, .original)
        XCTAssertEqual(BrowserInterfaceColor.hex(for: next.appearance.customInterfaceColor), BrowserInterfaceColor.defaultCustomHex)
        XCTAssertTrue(next.showsMascot)
    }

    private func luminance(_ rgb: [CGFloat]) -> CGFloat {
        let linear = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
    }
}
