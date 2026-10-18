import AppKit
import Foundation
import Observation

struct TabSession: Codable, Equatable, Sendable {
    /// `nil` for a new tab.
    var url: URL?
    var title: String
    /// The archived back-forward history and scroll position. WebKit's interaction state is an `NSData`.
    var interactionState: Data?
    var isPinned = false
    var groupID: UUID? = nil

    private enum CodingKeys: String, CodingKey { case url, title, interactionState, isPinned, groupID }

    init(url: URL?, title: String, interactionState: Data?, isPinned: Bool = false, groupID: UUID? = nil) {
        self.url = url; self.title = title; self.interactionState = interactionState
        self.isPinned = isPinned; self.groupID = groupID
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        url = try values.decodeIfPresent(URL.self, forKey: .url)
        title = try values.decode(String.self, forKey: .title)
        interactionState = try values.decodeIfPresent(Data.self, forKey: .interactionState)
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        groupID = try values.decodeIfPresent(UUID.self, forKey: .groupID)
    }
}

struct WindowSession: Codable, Equatable, Sendable {
    var tabs: [TabSession]
    var selectedIndex: Int
    /// Links a parked profile session to its physical browser window across launches.
    var profileWindowID: UUID? = nil
    var groups: [TabGroup] = []

    private enum CodingKeys: String, CodingKey { case tabs, selectedIndex, profileWindowID, groups }

    init(tabs: [TabSession], selectedIndex: Int, profileWindowID: UUID? = nil, groups: [TabGroup] = []) {
        self.tabs = tabs; self.selectedIndex = selectedIndex
        self.profileWindowID = profileWindowID; self.groups = groups
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tabs = try values.decode([TabSession].self, forKey: .tabs)
        selectedIndex = try values.decode(Int.self, forKey: .selectedIndex)
        profileWindowID = try values.decodeIfPresent(UUID.self, forKey: .profileWindowID)
        groups = try values.decodeIfPresent([TabGroup].self, forKey: .groups) ?? []
    }
}

struct SessionSnapshot: Codable, Equatable, Sendable {
    /// The windows open when the app last quit, reopened on launch.
    var windows: [WindowSession] = []
    /// The windows that were open before the last one closed, for Reopen All Windows from Last Session.
    var closedWindows: [WindowSession] = []
    /// Profile sessions retained behind another profile in the same physical window.
    var parkedWindows: [WindowSession] = []

    var version = 1
    private enum CodingKeys: String, CodingKey { case version, windows, closedWindows, parkedWindows }
    init(windows: [WindowSession] = [], closedWindows: [WindowSession] = [], parkedWindows: [WindowSession] = []) {
        self.windows = windows; self.closedWindows = closedWindows; self.parkedWindows = parkedWindows
    }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard version == 1, values.contains(.windows) || values.contains(.closedWindows) || values.contains(.parkedWindows) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported session format"))
        }
        windows = try values.decodeIfPresent([WindowSession].self, forKey: .windows) ?? []
        closedWindows = try values.decodeIfPresent([WindowSession].self, forKey: .closedWindows) ?? []
        parkedWindows = try values.decodeIfPresent([WindowSession].self, forKey: .parkedWindows) ?? []
    }
}

/// Saves the open windows and their tabs, and reopens them on launch. Windows join with `attach(_:)`; a window
/// that shouldn't be remembered, such as a private one, just doesn't.
@MainActor
@Observable
final class SessionStore {
    private static let saveDelay: Duration = .seconds(2)

    /// What History ▸ Reopen All Windows from Last Session opens.
    private(set) var reopenableWindows: [WindowSession]
    @ObservationIgnored private let file: StoreFile?
    @ObservationIgnored private var terminationObservation: NotificationObservation?
    @ObservationIgnored private var browsers: [WeakBrowser] = []
    /// Saved windows waiting for a window to restore them into.
    @ObservationIgnored private var pendingWindows: [WindowSession]
    @ObservationIgnored private var parkedWindows: [WindowSession]
    /// Windows already asked to open for `pendingWindows`, which shouldn't ask for more.
    @ObservationIgnored private var windowsBeingOpened = 0
    @ObservationIgnored private var isTerminating = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var observation = 0

    private struct WeakBrowser {
        weak var browser: BrowserModel?
        var ownerID: UUID?
        var isParked = false
        @MainActor var snapshot: WindowSession? {
            guard var snapshot = browser?.windowSession() else { return nil }
            snapshot.profileWindowID = ownerID
            return snapshot
        }
    }

    /// Pass `nil` to keep nothing between launches. Without `restoresWindows`, the windows open when the app quit
    /// wait to be reopened from the History menu instead of reopening on launch.
    init(file: StoreFile? = .applicationSupport(named: "Session.plist"), restoresWindows: Bool = true) {
        self.file = file
        // Read right away, since the first window restores the session as soon as it appears.
        let saved = file?.decodeNow(SessionSnapshot.self)
            ?? SessionSnapshot()
        pendingWindows = restoresWindows ? saved.windows : []
        parkedWindows = restoresWindows ? saved.parkedWindows : []
        reopenableWindows = !restoresWindows && !saved.windows.isEmpty ? saved.windows
            : saved.windows.isEmpty ? saved.closedWindows : []
        if !restoresWindows { reopenableWindows += saved.parkedWindows }
        terminationObservation = NotificationObservation(name: NSApplication.willTerminateNotification) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveBeforeQuitting() }
        }
    }

    private var openBrowsers: [BrowserModel] {
        browsers.compactMap(\.browser)
    }

    var storageURL: URL? { file?.url }

    func retrySave() {
        file?.writeNow(try? PropertyListEncoder.binary.encode(snapshot))
    }

    var hasPendingWindows: Bool { !pendingWindows.isEmpty }

    var nextWindowID: UUID? { pendingWindows.first?.profileWindowID }

    var snapshot: SessionSnapshot {
        SessionSnapshot(windows: browsers.filter { !$0.isParked }.compactMap(\.snapshot) + pendingWindows,
                        closedWindows: reopenableWindows,
                        parkedWindows: browsers.filter(\.isParked).compactMap(\.snapshot) + parkedWindows)
    }

    func setParked(_ parked: Bool, for browser: BrowserModel) {
        guard let index = browsers.firstIndex(where: { $0.browser === browser }) else { return }
        browsers[index].isParked = parked
        scheduleSave()
    }

    /// Remembers a window from now on. A window that opens while saved windows are waiting restores the next one.
    /// Returns how many more windows to open for the rest.
    func attach(_ browser: BrowserModel, ownerID: UUID? = nil, restoringOtherWindows: Bool = true) -> Int {
        guard !browser.isPrivate, !openBrowsers.contains(where: { $0 === browser }) else { return 0 }
        browsers.removeAll { $0.browser == nil }
        browsers.append(WeakBrowser(browser: browser, ownerID: ownerID))
        defer {
            observeBrowsers()
            scheduleSave()
        }
        if let ownerID, let index = parkedWindows.firstIndex(where: { $0.profileWindowID == ownerID }) {
            browser.restoreSession(parkedWindows.remove(at: index))
            return 0
        }
        // A switch can claim copied/legacy tabs, but cannot consume another physical window's restore request.
        guard let pendingIndex = pendingWindows.indices.first(where: {
            restoringOtherWindows || pendingWindows[$0].profileWindowID == nil
        }) else { return 0 }
        browser.restoreSession(pendingWindows.remove(at: pendingIndex))
        guard restoringOtherWindows else { return 0 }
        if windowsBeingOpened > 0 {
            windowsBeingOpened -= 1
            return 0
        }
        windowsBeingOpened = pendingWindows.count
        return pendingWindows.count
    }

    /// A closed physical window may have saved profiles that have not been visited since launch.
    func closeParkedWindow(ownerID: UUID) {
        guard !isTerminating else { return }
        let closed = parkedWindows.filter { $0.profileWindowID == ownerID }
        guard !closed.isEmpty else { return }
        reopenableWindows += closed
        parkedWindows.removeAll { $0.profileWindowID == ownerID }
        scheduleSave()
    }

    /// Forgets a window the user closed. Closing the last one keeps the windows for reopening later.
    func detach(_ browser: BrowserModel) {
        guard !isTerminating, openBrowsers.contains(where: { $0 === browser }) else { return }
        if openBrowsers.count == 1 {
            reopenableWindows = [browser.windowSession()]
        }
        browsers.removeAll { $0.browser == nil || $0.browser === browser }
        observeBrowsers()
        scheduleSave()
    }

    /// Restores the first window into `browser` when it only has a new tab, and returns how many windows to open
    /// for the rest.
    func reopenLastSession(reusing browser: BrowserModel?) -> Int {
        var windows = reopenableWindows
        reopenableWindows = []
        if let browser, browser.isBlank, !windows.isEmpty {
            browser.restoreSession(windows.removeFirst())
        }
        pendingWindows += windows
        windowsBeingOpened += windows.count
        scheduleSave()
        return windows.count
    }

    /// Forgets the windows waiting to be reopened, for when all history is cleared.
    func forgetClosedWindows() {
        reopenableWindows = []
        scheduleSave()
    }

    /// Saves again whenever a window's tabs, their addresses or titles, or its selected tab change.
    private func observeBrowsers() {
        observation += 1
        let current = observation
        withObservationTracking {
            for browser in openBrowsers {
                _ = browser.activeTabID
                _ = browser.groups
                for tab in browser.tabs {
                    _ = tab.url
                    _ = tab.pageTitle
                    _ = tab.isNewTab
                    _ = tab.isPinned
                    _ = tab.groupID
                }
            }
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.observation == current else { return }
                self.observeBrowsers()
                self.scheduleSave()
            }
        }
    }

    private func scheduleSave() {
        guard let file, !isTerminating else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard let self, !Task.isCancelled else { return }
            let snapshot = snapshot
            file.write { try? PropertyListEncoder.binary.encode(snapshot) }
        }
    }

    /// Prevent an unloaded profile's session from recreating files after explicit deletion.
    func disableWrites() {
        isTerminating = true
        saveTask?.cancel()
        file?.disableWrites()
    }

    /// Saves the windows as they are, and ignores them closing as the app quits.
    func saveBeforeQuitting() {
        isTerminating = true
        saveTask?.cancel()
        file?.writeNow(try? PropertyListEncoder.binary.encode(snapshot))
    }
}
