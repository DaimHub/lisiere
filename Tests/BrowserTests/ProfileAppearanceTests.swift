import AppKit
import WebKit
import XCTest
@testable import Browser

@MainActor
final class ProfileAppearanceTests: XCTestCase {
    func testIndependentThemesAccentsAndMascotsPersistAndCopyWithProfile() throws {
        let suite = "ProfileAppearanceTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        let store = ProfileStore(root: root, defaults: defaults)
        defer {
            for profile in store.profiles where !profile.isInitial {
                defaults.removePersistentDomain(forName: ProfileStore.defaultsDomain(for: profile.id))
            }
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let personal = try XCTUnwrap(store.context(for: BrowserProfile.initialID))
        let work = try store.create(name: "Work")
        let workContext = try XCTUnwrap(store.context(for: work.id))
        let first = personal.makeBrowser()
        let second = workContext.makeBrowser()
        defer { first.releaseClosedWindow(); second.releaseClosedWindow() }
        personal.preferences.appearance.selection = .light
        personal.preferences.accent = .rose
        personal.preferences.mascot = .lapin
        workContext.preferences.appearance.selection = .dark
        workContext.preferences.accent = .custom
        workContext.preferences.customAccent = try XCTUnwrap(AccentColor(hex: "#19b6a4"))
        workContext.preferences.mascot = .nuage
        XCTAssertEqual(first.activeTab?.webView?.appearance?.name, .aqua)
        XCTAssertEqual(second.activeTab?.webView?.appearance?.name, .darkAqua)
        XCTAssertEqual(personal.preferences.accent, .rose)
        let restarted = ProfileStore(root: root, defaults: defaults)
        let saved = try XCTUnwrap(restarted.context(for: work.id))
        XCTAssertEqual(saved.preferences.appearance.selection, .dark)
        XCTAssertEqual(saved.preferences.accent, .custom)
        XCTAssertEqual(saved.preferences.customAccent.hex, "19B6A4")
        XCTAssertEqual(saved.preferences.mascot, .nuage)
        let copy = try store.create(name: "Copy", copying: work.id)
        let copied = try XCTUnwrap(store.context(for: copy.id))
        XCTAssertEqual(copied.preferences.appearance.selection, .dark)
        XCTAssertEqual(copied.preferences.accent, .custom)
        XCTAssertEqual(copied.preferences.customAccent.hex, "19B6A4")
        copied.preferences.customAccent = try XCTUnwrap(AccentColor(hex: "000000"))
        XCTAssertEqual(workContext.preferences.customAccent.hex, "19B6A4")
        XCTAssertEqual(personal.preferences.accent, .rose)
        XCTAssertEqual(copied.preferences.mascot, .nuage)
        XCTAssertNotEqual(copied.browsingData.dataStore.identifier, workContext.browsingData.dataStore.identifier)
    }

    func testCustomHexValidationAndColorPickerRoundTrip() throws {
        XCTAssertEqual(AccentColor(hex: "  #1aF  ")?.hex, "11AAFF")
        for invalid in ["", "#", "12", "1234", "12345678", "GGGGGG", "-12345", "１２３", "#12 456"] {
            XCTAssertNil(AccentColor(hex: invalid), invalid)
        }
        let color = try XCTUnwrap(AccentColor(color: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.3)))
        XCTAssertEqual(color.hex, "336699")
    }

    func testExistingAccentsAndInvalidCustomValuesHaveSafeDefaults() throws {
        let suite = "AccentMigrationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for accent in ProfileAccent.presets {
            defaults.set(accent.rawValue, forKey: "profileAccent")
            XCTAssertEqual(ProfilePreferences(defaults: defaults).accent, accent)
        }
        defaults.set("custom", forKey: "profileAccent")
        defaults.set("invalid", forKey: "profileCustomAccent")
        XCTAssertEqual(ProfilePreferences(defaults: defaults).resolvedAccent, .defaultCustom)
        let preferences = ProfilePreferences(defaults: defaults)
        preferences.customAccent = try XCTUnwrap(AccentColor(hex: "FFEE00"))
        preferences.accent = .blue
        let restored = ProfilePreferences(defaults: defaults)
        XCTAssertEqual(restored.accent, .blue)
        XCTAssertEqual(restored.customAccent.hex, "FFEE00")
        restored.accent = .custom
        XCTAssertEqual(restored.resolvedAccent.hex, "FFEE00")
        let temporary = ProfilePreferences()
        temporary.accent = .custom
        temporary.customAccent = try XCTUnwrap(AccentColor(hex: "000000"))
        XCTAssertEqual(ProfilePreferences().customAccent, .defaultCustom)
    }

    func testPrivateControllerDoesNotSelectOrLoadItsOriginProfile() throws {
        let suite = "PrivateProfileTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let profiles = ProfileStore(root: nil, defaults: defaults)
        let selected = profiles.selectedID
        // Even a nonexistent regular profile cannot prevent a fresh private session.
        let owner = try ProfileWindowController(profiles: profiles, profileID: UUID(), isPrivate: true)
        defer { owner.close() }
        XCTAssertNil(owner.browser.profileID)
        XCTAssertEqual(owner.browser.appearance.selection, .dark)
        XCTAssertTrue(owner.privateBookmarks.bookmarks.isEmpty)
        XCTAssertTrue(owner.browser.downloads.items.isEmpty)
        owner.switchTo(BrowserProfile.initialID)
        owner.becameKey()
        XCTAssertNil(owner.browser.profileID)
        XCTAssertEqual(profiles.selectedID, selected)
        XCTAssertNil(profiles.lastActiveWindow)
    }

    func testDialogWaitsForItsProfileToBecomeVisibleAgain() async throws {
        let browser = BrowserModel()
        defer { browser.releaseClosedWindow() }
        let tab = try XCTUnwrap(browser.activeTab)
        browser.setWorkspaceActive(false)
        var completed = false
        let pending = Task { let selected = await tab.waitUntilSelected(); completed = true; return selected }
        await Task.yield()
        XCTAssertFalse(completed)
        browser.setWorkspaceActive(true)
        let result = await pending.value
        XCTAssertTrue(result)
    }
}
