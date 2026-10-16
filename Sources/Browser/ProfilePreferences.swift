import Foundation
import Observation
import SwiftUI

/// Preferences belong to a profile; only OS integration and software updates remain app-wide.
@MainActor
@Observable
final class ProfilePreferences {
    let defaults: UserDefaults?
    let appearance: AppearanceStore
    var accent: ProfileAccent { didSet { defaults?.set(accent.rawValue, forKey: "profileAccent") } }
    var customAccent: AccentColor { didSet { defaults?.set(customAccent.hex, forKey: "profileCustomAccent") } }
    var resolvedAccent: AccentColor { accent.resolved(custom: customAccent) }
    var accentColor: Color { resolvedAccent.color }
    var mascot: Mascot { didSet { defaults?.set(mascot.rawValue, forKey: Mascot.storageKey) } }
    var mascotPalette: MascotPalette { didSet { defaults?.set(mascotPalette.rawValue, forKey: MascotPalette.storageKey) } }
    var searchEngine: SearchEngine { didSet { defaults?.set(searchEngine.rawValue, forKey: SearchEngine.storageKey) } }
    var newTabPage: NewTabPage { didSet { defaults?.set(newTabPage.rawValue, forKey: NewTabPage.storageKey) } }
    var toolbarLayout: BrowserToolbarLayout {
        didSet { defaults?.set(toolbarLayout.storedValue, forKey: BrowserToolbarLayout.storageKey) }
    }
    var tabLayout: TabLayout { didSet { defaults?.set(tabLayout.rawValue, forKey: TabLayout.storageKey) } }
    var bookmarksBarVisibility: BookmarksBarVisibility {
        didSet { defaults?.set(bookmarksBarVisibility.rawValue, forKey: BookmarksBarVisibility.storageKey) }
    }
    var restoresWindows: Bool { didSet { defaults?.set(restoresWindows, forKey: SessionPreferences.restoresWindowsKey) } }
    var asksWhereToSave: Bool { didSet { defaults?.set(asksWhereToSave, forKey: DownloadPreferences.asksWhereToSaveKey) } }

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        appearance = AppearanceStore(defaults: defaults, appliesToApplication: false)
        accent = defaults?.string(forKey: "profileAccent").flatMap(ProfileAccent.init(rawValue:)) ?? .sage
        customAccent = defaults?.string(forKey: "profileCustomAccent").flatMap(AccentColor.init(hex:)) ?? .defaultCustom
        mascot = defaults?.string(forKey: Mascot.storageKey).flatMap(Mascot.init(rawValue:)) ?? (defaults == nil ? .defaultChoice : .current())
        mascotPalette = defaults?.string(forKey: MascotPalette.storageKey).flatMap(MascotPalette.init(rawValue:)) ?? (defaults == nil ? .defaultChoice : .current())
        searchEngine = defaults?.string(forKey: SearchEngine.storageKey).flatMap(SearchEngine.init) ?? .google
        newTabPage = defaults?.string(forKey: NewTabPage.storageKey).flatMap(NewTabPage.init) ?? .startPage
        toolbarLayout = BrowserToolbarLayout(storedValue: defaults?.stringArray(forKey: BrowserToolbarLayout.storageKey))
        tabLayout = defaults?.string(forKey: TabLayout.storageKey).flatMap(TabLayout.init) ?? .horizontal
        bookmarksBarVisibility = defaults?.string(forKey: BookmarksBarVisibility.storageKey)
            .flatMap(BookmarksBarVisibility.init) ?? .always
        restoresWindows = defaults?.object(forKey: SessionPreferences.restoresWindowsKey) as? Bool ?? true
        asksWhereToSave = defaults?.bool(forKey: DownloadPreferences.asksWhereToSaveKey) ?? false
    }

    // Copy explicit settings only: never credentials, grants, history, caches, or WebKit interaction state.
    static let copiedKeys = ["profileAccent", "profileCustomAccent", BrowserAppearance.storageKey, WebPageAppearance.storageKey,
                             WebPageAppearance.separateStorageKey, Mascot.storageKey, MascotPalette.storageKey,
                             SearchEngine.storageKey, NewTabPage.storageKey, TabLayout.storageKey, BrowserToolbarLayout.storageKey,
                             BookmarksBarVisibility.storageKey, SessionPreferences.restoresWindowsKey,
                             DownloadPreferences.asksWhereToSaveKey, "blocksTrackers", "trackerBlockingExceptions",
                             "offersToSavePasswords", "neverSavePasswordSites", "pageZoomLevels", "bookmarks"]
    static let ownedKeys = copiedKeys + ["sitePermissions", "trackerRuleListSignature"]
}
