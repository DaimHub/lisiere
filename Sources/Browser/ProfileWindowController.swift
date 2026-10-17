import AppKit
import Observation

/// One physical window, with a distinct, retained BrowserModel for each visited profile.
/// Web views and their data stores never migrate between profiles or other windows.
@MainActor
@Observable
final class ProfileWindowController {
    let profiles: ProfileStore
    let id: UUID
    let isPrivate: Bool
    private(set) var browser: BrowserModel
    private(set) var isClosed = false
    let additionalWindows: Int
    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored private var browsers: [UUID: BrowserModel] = [:]
    @ObservationIgnored var onActivate: ((BrowserModel) -> Void)?
    let privateBookmarks = BookmarkStore(defaults: nil)
    private(set) var privateBrowsingData: BrowsingData?

    init(profiles: ProfileStore, profileID: UUID, isPrivate: Bool = false) throws {
        self.profiles = profiles
        self.isPrivate = isPrivate
        if isPrivate {
            id = UUID()
            browser = .makePrivate()
            additionalWindows = 0
            browsers[id] = browser
            privateBrowsingData = BrowsingData(history: HistoryStore(file: nil), session: SessionStore(file: nil),
                                               dataStore: browser.websiteDataStore, favicons: browser.favicons)
            browser.profileWindow = self
            return
        }
        guard let context = profiles.context(for: profileID) else { throw ProfileStore.Failure.missingProfile }
        let ownerID = isPrivate ? UUID() : context.session.nextWindowID ?? UUID()
        let model = context.makeBrowser(isPrivate: isPrivate)
        id = ownerID
        browser = model
        additionalWindows = isPrivate ? 0 : context.session.attach(model, ownerID: ownerID)
        browsers[profileID] = browser
        browser.profileWindow = self
        profiles.register(browser)
    }

    func connect(_ window: NSWindow?) {
        self.window = window
        browser.window = window
        if window?.isKeyWindow == true { becameKey() }
    }

    func becameKey() {
        guard !isClosed, let id = browser.profileID else { return }
        profiles.lastActiveWindow = self
        browser.preferences.mascot.applyDockIcon(palette: browser.preferences.mascotPalette)
        do { try profiles.select(id) } catch { profiles.errorMessage = error.localizedDescription }
    }

    func switchBy(_ direction: Int) {
        guard let current = browser.profileID, let next = profiles.adjacentProfile(to: current, direction: direction) else { return }
        switchTo(next)
    }

    func switchTo(_ profileID: UUID) {
        guard !isClosed, !isPrivate, browser.profileID != profileID else { return }
        do {
            guard let context = profiles.context(for: profileID) else { throw ProfileStore.Failure.missingProfile }
            try profiles.select(profileID)
            let next: BrowserModel
            if let retained = browsers[profileID] {
                next = retained
                if !isPrivate { context.session.setParked(false, for: next) }
            } else {
                next = context.makeBrowser(isPrivate: isPrivate)
                if !isPrivate { _ = context.session.attach(next, ownerID: id, restoringOtherWindows: false) }
                browsers[profileID] = next
                next.profileWindow = self
                profiles.register(next)
            }
            if !isPrivate, let previousID = browser.profileID {
                profiles.context(for: previousID)?.session.setParked(true, for: browser)
            }
            ExternalURLRouter.shared.unregister(browser)
            browser.setWorkspaceActive(false)
            browser.window = nil
            browser = next
            browser.setWorkspaceActive(true)
            browser.window = window
            profiles.lastActiveWindow = self
            browser.preferences.mascot.applyDockIcon(palette: browser.preferences.mascotPalette)
            onActivate?(browser)
        } catch { profiles.errorMessage = error.localizedDescription }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        for (id, model) in browsers {
            if !isPrivate { profiles.context(for: id)?.session.detach(model) }
            profiles.unregister(model)
            ExternalURLRouter.shared.unregister(model)
            model.profileWindow = nil
            model.releaseClosedWindow()
        }
        if !isPrivate {
            for profile in profiles.availableProfiles {
                profiles.session(for: profile.id)?.closeParkedWindow(ownerID: id)
            }
        }
        browsers = [:]
        privateBrowsingData?.releaseDataStore()
        privateBrowsingData = nil
        if profiles.lastActiveWindow === self { profiles.lastActiveWindow = nil }
        window = nil
        onActivate = nil
    }
}
