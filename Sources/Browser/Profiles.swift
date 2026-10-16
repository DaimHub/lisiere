import AppKit
import Observation
import SwiftUI
import WebKit

enum ProfileIcon: String, Codable, CaseIterable, Identifiable {
    case person = "person.crop.circle"
    case briefcase = "briefcase"
    case house = "house"
    case book = "book"
    case globe = "globe"
    case code = "chevron.left.forwardslash.chevron.right"
    case leaf = "leaf"
    case star = "star"
    case heart = "heart"
    case game = "gamecontroller"
    case graduation = "graduationcap"
    case flask = "flask"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .person: "Personal"
        case .briefcase: "Work"
        case .house: "Home"
        case .book: "Reading"
        case .globe: "Explore"
        case .code: "Development"
        case .leaf: "Leaf"
        case .star: "Star"
        case .heart: "Heart"
        case .game: "Games"
        case .graduation: "Study"
        case .flask: "Research"
        }
    }
}

struct BrowserProfile: Codable, Identifiable, Equatable {
    // The original installation keeps WebKit.default() and the original file paths. Never copy site databases.
    static let initialID = UUID(uuidString: "C553390B-47B8-49C4-892D-4BB4F58BE317")!
    static let initial = BrowserProfile(id: initialID, name: "Personal")
    let id: UUID
    var name: String
    var icon: ProfileIcon = .person
    var pendingDeletion = false
    var isInitial: Bool { id == Self.initialID }
    private enum CodingKeys: String, CodingKey { case id, name, icon, pendingDeletion }
    init(id: UUID, name: String, icon: ProfileIcon = .person) {
        self.id = id; self.name = name; self.icon = icon
    }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        icon = try values.decodeIfPresent(ProfileIcon.self, forKey: .icon) ?? .person
        pendingDeletion = try values.decodeIfPresent(Bool.self, forKey: .pendingDeletion) ?? false
    }
}

/// A unique scene request allows several windows of the same profile.
struct ProfileWindowRequest: Codable, Hashable {
    var id = UUID()
    let profileID: UUID
}

@MainActor
final class ProfileContext {
    let id: UUID
    let defaults: UserDefaults
    let preferences: ProfilePreferences
    let bookmarks: BookmarkStore
    let downloads: DownloadManager
    let passwords: PasswordManager
    let contentBlocker: ContentBlocker
    let favicons: FaviconStore
    let history: HistoryStore
    let session: SessionStore
    let sitePermissions: SitePermissions
    let zoomLevels: ZoomStore
    let browsingData: BrowsingData
    private let files: [StoreFile]

    init(profile: BrowserProfile, directory: URL?, defaults: UserDefaults,
         restoresWindows: Bool?, dataStore: WKWebsiteDataStore) {
        id = profile.id
        self.defaults = defaults
        preferences = ProfilePreferences(defaults: defaults)
        bookmarks = BookmarkStore(defaults: defaults)
        downloads = DownloadManager(preferences: preferences)
        passwords = PasswordManager(storage: KeychainPasswordStorage(profileID: profile.isInitial ? nil : profile.id),
                                    defaults: defaults)
        contentBlocker = ContentBlocker(defaults: defaults, store: .default(),
                                        identifier: profile.isInitial ? "Trackers" : "Trackers-\(profile.id)")
        favicons = profile.isInitial ? FaviconStore() : FaviconStore(directory:
            (directory ?? FileManager.default.temporaryDirectory.appending(path: "Lisiere-\(profile.id)"))
                .appending(path: "Favicons"))
        let historyFile = directory.map { StoreFile(url: $0.appending(path: "History.plist")) }
        let sessionFile = directory.map { StoreFile(url: $0.appending(path: "Session.plist")) }
        files = [historyFile, sessionFile].compactMap { $0 }
        history = HistoryStore(file: historyFile)
        session = SessionStore(file: sessionFile, restoresWindows: restoresWindows ?? preferences.restoresWindows)
        sitePermissions = SitePermissions(defaults: defaults)
        zoomLevels = ZoomStore(defaults: defaults)
        browsingData = BrowsingData(history: history, session: session, dataStore: dataStore, favicons: favicons)
    }

    func makeBrowser(downloads: DownloadManager? = nil, isPrivate: Bool = false) -> BrowserModel {
        if isPrivate {
            return .makePrivate(downloads: downloads ?? self.downloads, profileID: id,
                                preferences: preferences, contentBlocker: contentBlocker)
        }
        return BrowserModel(downloads: downloads ?? self.downloads, sitePermissions: sitePermissions, history: history,
                            zoomLevels: zoomLevels, websiteDataStore: browsingData.dataStore,
                            passwords: passwords, profileID: id, preferences: preferences,
                            contentBlocker: contentBlocker, favicons: favicons)
    }

    func prepareForDeletion() {
        files.forEach { $0.disableWrites() }
        downloads.releaseFinishedDownloads()
        browsingData.releaseDataStore()
    }
}

/// Owns profile identity and resources, never retargets an existing WKWebView to another profile.
@MainActor
@Observable
final class ProfileStore {
    private struct Manifest: Codable {
        var version = 1
        var profiles: [BrowserProfile] = [.initial]
        var selectedID = BrowserProfile.initialID
    }

    enum Failure: LocalizedError {
        case invalidName, duplicateName, missingProfile, lastProfile, openWindows, activeDownloads, invalidManifest
        var errorDescription: String? {
            switch self {
            case .invalidName: "Use a profile name between 1 and 40 characters."
            case .duplicateName: "A profile already has that name."
            case .missingProfile: "This profile is unavailable."
            case .lastProfile: "Keep at least one profile."
            case .openWindows: "Close windows that use this profile, including windows where it is in the background and private windows, before deleting it."
            case .activeDownloads: "Wait for this profile’s downloads to finish or cancel them before deleting it."
            case .invalidManifest: "The profile list could not be read. Your data has not been changed."
            }
        }
    }

    private(set) var profiles: [BrowserProfile] = [.initial]
    private(set) var selectedID = BrowserProfile.initialID
    private(set) var loadError: String?
    var errorMessage: String?
    var settingsTab = SettingsTab.general
    @ObservationIgnored weak var lastActiveWindow: ProfileWindowController?
    private(set) var deletingID: UUID?
    @ObservationIgnored private let root: URL?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let restoresWindows: Bool?
    @ObservationIgnored private let dataStoreFactory: (BrowserProfile) -> WKWebsiteDataStore
    @ObservationIgnored private var contexts: [UUID: ProfileContext] = [:]
    @ObservationIgnored private var browsers: [WeakBrowser] = []
    @ObservationIgnored private var restoredAtLaunch = false

    private struct WeakBrowser { weak var value: BrowserModel? }

    init(root: URL? = StoreFile.applicationSupport(named: "Profiles.plist").url.deletingLastPathComponent(),
         defaults: UserDefaults = .standard, restoresWindows: Bool? = nil,
         dataStoreFactory: @escaping (BrowserProfile) -> WKWebsiteDataStore = {
             profile in
             autoreleasepool { profile.isInitial ? .default() : WKWebsiteDataStore(forIdentifier: profile.id) }
         }) {
        self.root = root
        self.defaults = defaults
        self.restoresWindows = restoresWindows
        self.dataStoreFactory = dataStoreFactory
        guard let file = manifestURL, FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let saved = try PropertyListDecoder().decode(Manifest.self, from: Data(contentsOf: file))
            guard saved.version == 1, !saved.profiles.isEmpty,
                  Set(saved.profiles.map(\.id)).count == saved.profiles.count,
                  saved.profiles.contains(where: { $0.id == saved.selectedID && !$0.pendingDeletion }),
                  saved.profiles.allSatisfy({
                      !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          && $0.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000")
                          && $0.id != UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")
                  })
            else { throw Failure.invalidManifest }
            profiles = saved.profiles
            selectedID = saved.selectedID
        } catch {
            // Do not reset a damaged registry and silently orphan existing data stores.
            loadError = Failure.invalidManifest.localizedDescription
        }
    }

    var availableProfiles: [BrowserProfile] { profiles.filter { !$0.pendingDeletion } }
    /// Settings or a private window may select a parked profile before quit. Restore an actual visible
    /// session first, so that selection alone doesn't manufacture an extra physical window on launch.
    var defaultWindowProfileID: UUID {
        guard !restoredAtLaunch, context(for: selectedID)?.session.hasPendingWindows != true else { return selectedID }
        return availableProfiles.first { context(for: $0.id)?.session.hasPendingWindows == true }?.id ?? selectedID
    }

    private var manifestURL: URL? { root?.appending(path: "Profiles.plist") }
    func profile(_ id: UUID) -> BrowserProfile? { profiles.first { $0.id == id } }
    func name(_ id: UUID) -> String { profile(id)?.name ?? "Profile" }

    func directory(for profile: BrowserProfile) -> URL? {
        profile.isInitial ? root : root?.appending(path: "Profiles/\(profile.id.uuidString)", directoryHint: .isDirectory)
    }

    static func defaultsDomain(for id: UUID) -> String {
        "\(Bundle.main.bundleIdentifier ?? "io.github.daimhub.lisiere").profile.\(id)"
    }

    private func preferencesDefaults(for profile: BrowserProfile) -> UserDefaults {
        profile.isInitial ? defaults : UserDefaults(suiteName: Self.defaultsDomain(for: profile.id))!
    }

    func context(for id: UUID) -> ProfileContext? {
        guard loadError == nil, let profile = profile(id), !profile.pendingDeletion else { return nil }
        if let context = contexts[id] { return context }
        let context = ProfileContext(profile: profile, directory: directory(for: profile), defaults: preferencesDefaults(for: profile),
                                     restoresWindows: restoresWindows, dataStore: dataStoreFactory(profile))
        contexts[id] = context
        return context
    }

    private func save(_ profiles: [BrowserProfile], selectedID: UUID) throws {
        guard loadError == nil else { throw Failure.invalidManifest }
        if let file = manifestURL {
            let data = try PropertyListEncoder.binary.encode(Manifest(profiles: profiles, selectedID: selectedID))
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        }
        self.profiles = profiles
        self.selectedID = selectedID
    }

    private func validatedName(_ text: String, excluding id: UUID? = nil) throws -> String {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(name.count), !name.contains(where: { $0.isNewline }) else { throw Failure.invalidName }
        guard !profiles.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame })
        else { throw Failure.duplicateName }
        return name
    }

    @discardableResult
    func create(name: String, icon: ProfileIcon = .person, copying sourceID: UUID? = nil) throws -> BrowserProfile {
        let profile = BrowserProfile(id: UUID(), name: try validatedName(name), icon: icon)
        // Prepare an independent snapshot before publishing the new identity. No live references are copied.
        let target = preferencesDefaults(for: profile)
        do {
            if let sourceID {
                guard let source = context(for: sourceID) else { throw Failure.missingProfile }
                for key in ProfilePreferences.copiedKeys {
                    if let value = source.defaults.object(forKey: key) { target.set(value, forKey: key) }
                }
                let snapshot = source.session.snapshot
                let live = snapshot.windows + snapshot.parkedWindows
                let windows = live.isEmpty ? snapshot.closedWindows : live
                let clean = windows.map { window in
                    WindowSession(tabs: window.tabs.map { TabSession(url: $0.url, title: $0.title, interactionState: nil) },
                                  selectedIndex: window.selectedIndex)
                }
                if let directory = directory(for: profile), !clean.isEmpty {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try PropertyListEncoder.binary.encode(SessionSnapshot(windows: clean))
                        .write(to: directory.appending(path: "Session.plist"), options: .atomic)
                }
            }
            try save(profiles + [profile], selectedID: selectedID)
            return profile
        } catch {
            target.removePersistentDomain(forName: Self.defaultsDomain(for: profile.id))
            if let directory = directory(for: profile) { try? FileManager.default.removeItem(at: directory) }
            throw error
        }
    }

    func rename(_ id: UUID, to name: String, icon: ProfileIcon? = nil) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id && !$0.pendingDeletion }) else {
            throw Failure.missingProfile
        }
        var updated = profiles
        updated[index].name = try validatedName(name, excluding: id)
        if let icon { updated[index].icon = icon }
        try save(updated, selectedID: selectedID)
    }

    func select(_ id: UUID) throws {
        guard profile(id)?.pendingDeletion == false else { throw Failure.missingProfile }
        if selectedID != id { try save(profiles, selectedID: id) }
    }

    func register(_ browser: BrowserModel) {
        browsers.removeAll { $0.value == nil || $0.value === browser }
        browsers.append(WeakBrowser(value: browser))
    }

    func unregister(_ browser: BrowserModel) {
        browsers.removeAll { $0.value == nil || $0.value === browser }
    }

    func adjacentProfile(to id: UUID, direction: Int) -> UUID? {
        let profiles = availableProfiles
        guard profiles.count > 1, let index = profiles.firstIndex(where: { $0.id == id }) else { return nil }
        let next = (index + (direction > 0 ? 1 : -1) + profiles.count) % profiles.count
        return profiles[next].id
    }

    func switchProfile(from id: UUID, direction: Int, in browser: BrowserModel? = nil, openWindow: OpenWindowAction) {
        guard let next = adjacentProfile(to: id, direction: direction) else { return }
        activate(next, in: browser, openWindow: openWindow)
    }

    /// Change the focused browser's profile without opening or stealing another window.
    /// Settings reuses the last active browser; only an app with no browser window opens a new one.
    func activate(_ id: UUID, in browser: BrowserModel? = nil, openWindow: OpenWindowAction) {
        let visible = browsers.compactMap(\.value).filter { $0.window != nil }.compactMap(\.profileWindow)
        if let owner = browser?.profileWindow ?? lastActiveWindow ?? visible.first, !owner.isClosed {
            owner.switchTo(id)
            if owner.window?.isMiniaturized == true { owner.window?.deminiaturize(nil) }
            owner.window?.makeKeyAndOrderFront(nil)
        } else {
            do {
                try select(id)
                openWindow(id: BrowserApp.windowID, value: ProfileWindowRequest(profileID: id))
            } catch { errorMessage = error.localizedDescription }
        }
    }

    /// Once the first normal window appears, reopen the other profiles that had windows at quit.
    func restoreOtherProfiles(except id: UUID, openWindow: OpenWindowAction) {
        guard !restoredAtLaunch else { return }
        restoredAtLaunch = true
        for profile in availableProfiles where profile.id != id {
            if context(for: profile.id)?.session.hasPendingWindows == true {
                openWindow(id: BrowserApp.windowID, value: ProfileWindowRequest(profileID: profile.id))
            }
        }
    }

    static func clearWebsiteData(in store: WKWebsiteDataStore) async {
        // Stop service workers as well as clearing data before releasing the store's network session.
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    static func removeWebsiteDataStore(_ id: UUID) async throws {
        // WebKit releases closed views asynchronously. Retry briefly, then leave a visible, retryable tombstone.
        for attempt in 0..<30 {
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    WKWebsiteDataStore.remove(forIdentifier: id) { error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume() }
                    }
                }
                return
            } catch {
                guard attempt < 29, (error as NSError).domain == "WKWebSiteDataStore" else { throw error }
                try await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Called only after the product's destructive confirmation. A durable tombstone makes failures retryable;
    /// a half-deleted profile cannot reopen, including after a crash.
    func delete(_ id: UUID) async throws {
        guard deletingID == nil else { throw Failure.missingProfile }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw Failure.missingProfile }
        guard availableProfiles.contains(where: { $0.id != id }) else { throw Failure.lastProfile }
        guard !browsers.compactMap(\.value).contains(where: { $0.profileID == id }) else { throw Failure.openWindows }
        guard contexts[id]?.downloads.isDownloading != true else { throw Failure.activeDownloads }
        deletingID = id
        defer { deletingID = nil }
        let profile = profiles[index]
        var updated = profiles
        updated[index].pendingDeletion = true
        let nextID = selectedID == id ? availableProfiles.first(where: { $0.id != id })!.id : selectedID
        try save(updated, selectedID: nextID)
        // Password errors keep the visible tombstone retryable, rather than silently leaving secrets behind.
        let passwordStore = contexts[id]?.passwords ?? PasswordManager(
            storage: KeychainPasswordStorage(profileID: profile.isInitial ? nil : profile.id))
        try passwordStore.removeAll()
        let blocker = contexts[id]?.contentBlocker ?? ContentBlocker(defaults: preferencesDefaults(for: profile),
            store: .default(), identifier: profile.isInitial ? "Trackers" : "Trackers-\(profile.id)")
        await blocker.removeCompiledRules()
        await contexts[id]?.favicons.clear(since: .distantPast)
        await Self.clearWebsiteData(in: dataStoreFactory(profile))
        contexts[id]?.prepareForDeletion()
        contexts[id] = nil
        if !profile.isInitial { try await Self.removeWebsiteDataStore(id) }
        if let directory = directory(for: profile) {
            // The initial directory also contains shared data and the registry. Remove only its owned files.
            let targets = profile.isInitial ? ["History.plist", "Session.plist"].map { directory.appending(path: $0) }
                : [directory]
            for target in targets where FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
        }
        if profile.isInitial {
            ProfilePreferences.ownedKeys.forEach { defaults.removeObject(forKey: $0) }
        } else {
            preferencesDefaults(for: profile).removePersistentDomain(forName: Self.defaultsDomain(for: profile.id))
        }
        try save(profiles.filter { $0.id != id }, selectedID: nextID)
    }
}
