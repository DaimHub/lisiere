import Foundation
import Observation

/// Preferences belong to a profile; only OS integration and software updates remain app-wide.
@MainActor
@Observable
final class ProfilePreferences {
    let defaults: UserDefaults?
    var searchEngine: SearchEngine { didSet { defaults?.set(searchEngine.rawValue, forKey: SearchEngine.storageKey) } }
    var newTabPage: NewTabPage { didSet { defaults?.set(newTabPage.rawValue, forKey: NewTabPage.storageKey) } }
    var tabLayout: TabLayout { didSet { defaults?.set(tabLayout.rawValue, forKey: TabLayout.storageKey) } }
    var bookmarksBarVisibility: BookmarksBarVisibility {
        didSet { defaults?.set(bookmarksBarVisibility.rawValue, forKey: BookmarksBarVisibility.storageKey) }
    }
    var restoresWindows: Bool { didSet { defaults?.set(restoresWindows, forKey: SessionPreferences.restoresWindowsKey) } }
    var asksWhereToSave: Bool { didSet { defaults?.set(asksWhereToSave, forKey: DownloadPreferences.asksWhereToSaveKey) } }

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        searchEngine = defaults?.string(forKey: SearchEngine.storageKey).flatMap(SearchEngine.init) ?? .google
        newTabPage = defaults?.string(forKey: NewTabPage.storageKey).flatMap(NewTabPage.init) ?? .startPage
        tabLayout = defaults?.string(forKey: TabLayout.storageKey).flatMap(TabLayout.init) ?? .horizontal
        bookmarksBarVisibility = defaults?.string(forKey: BookmarksBarVisibility.storageKey)
            .flatMap(BookmarksBarVisibility.init) ?? .always
        restoresWindows = defaults?.object(forKey: SessionPreferences.restoresWindowsKey) as? Bool ?? true
        asksWhereToSave = defaults?.bool(forKey: DownloadPreferences.asksWhereToSaveKey) ?? false
    }

    // Copy explicit settings only: never credentials, grants, history, caches, or WebKit interaction state.
    static let copiedKeys = [SearchEngine.storageKey, NewTabPage.storageKey, TabLayout.storageKey,
                             BookmarksBarVisibility.storageKey, SessionPreferences.restoresWindowsKey,
                             DownloadPreferences.asksWhereToSaveKey, "blocksTrackers", "trackerBlockingExceptions",
                             "offersToSavePasswords", "neverSavePasswordSites", "pageZoomLevels", "bookmarks"]
    static let ownedKeys = copiedKeys + ["sitePermissions", "trackerRuleListSignature"]
}
