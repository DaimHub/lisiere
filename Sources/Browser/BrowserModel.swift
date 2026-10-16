import AppKit
import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class BrowserModel {
    let profileID: UUID?
    let appearance: AppearanceStore
    private(set) var isActiveInWorkspace = true
    let preferences: ProfilePreferences
    let contentBlocker: ContentBlocker
    let favicons: FaviconStore
    let downloads: DownloadManager
    let sitePermissions: SitePermissions
    /// `nil` for a window whose pages aren't remembered.
    let history: HistoryStore?
    let zoomLevels: ZoomStore
    /// Shared by the window's tabs. A private window's keeps its cookies and site data in memory, apart from
    /// other windows, until the window closes.
    private(set) var websiteDataStore: WKWebsiteDataStore
    /// Offers to save sign-ins and fills them in. `nil` for a window whose pages aren't remembered.
    let passwords: PasswordManager?
    /// The window showing these tabs, so links from other apps can open in the frontmost one.
    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored weak var profileWindow: ProfileWindowController?

    private(set) var tabs: [BrowserTab] = []
    private var closedTabs: [ClosedTab] = []
    var activeTabID: UUID? {
        didSet {
            guard oldValue != activeTabID else { return }
            if let previousTab = tab(withID: oldValue) {
                // Keep a preview of the page being left for background-tab hover cards.
                previousTab.captureThumbnail(afterScreenUpdates: false)
                previousTab.lastActive = .now
            }
            activeTab?.restore()
            activeTab?.didBecomeSelected()
        }
    }
    var addressFocusRequest = 0
    var findFocusRequest = 0
    var isShowingHistory = false
    var isShowingClearData = false
    @ObservationIgnored private var suspender: TabSuspender?

    private struct ClosedTab {
        let url: URL?
        let title: String
        /// The tab's back-forward history, restored when it reopens.
        let interactionState: Any?
    }

    init(downloads: DownloadManager = DownloadManager(), sitePermissions: SitePermissions = .shared,
         history: HistoryStore? = nil, zoomLevels: ZoomStore = .shared,
         websiteDataStore: WKWebsiteDataStore = .default(), passwords: PasswordManager? = nil, profileID: UUID? = nil,
         preferences: ProfilePreferences? = nil, contentBlocker: ContentBlocker = .shared,
         favicons: FaviconStore = .shared, appearance: AppearanceStore? = nil) {
        let privateMode = !websiteDataStore.isPersistent
        let ownedPreferences = privateMode ? ProfilePreferences() : (preferences ?? ProfilePreferences(defaults: .standard))
        if privateMode {
            ownedPreferences.appearance.selection = .dark
            ownedPreferences.appearance.pageSelection = .dark
        }
        self.appearance = privateMode ? ownedPreferences.appearance : (appearance ?? ownedPreferences.appearance)
        self.preferences = ownedPreferences
        self.contentBlocker = privateMode ? ContentBlocker(defaults: nil, store: .default(), identifier: "Private-Trackers") : contentBlocker
        self.favicons = privateMode
            ? FaviconStore(directory: FileManager.default.temporaryDirectory.appending(path: "Private-\(UUID())")) : favicons
        self.profileID = privateMode ? nil : profileID
        self.downloads = privateMode ? DownloadManager(preferences: ownedPreferences) : downloads
        self.sitePermissions = privateMode ? SitePermissions() : sitePermissions
        self.history = privateMode ? nil : history
        self.zoomLevels = privateMode ? ZoomStore(defaults: nil) : zoomLevels
        self.websiteDataStore = websiteDataStore
        self.passwords = privateMode ? nil : passwords
        addTab()
        suspender = TabSuspender(browser: self)
    }

    /// A window that keeps nothing once it closes: no history, zoom levels, site permissions, or passwords, and
    /// cookies and site data its tabs share only with each other. Downloads still save.
    static func makePrivate(downloads: DownloadManager? = nil, profileID: UUID? = nil,
                            preferences: ProfilePreferences? = nil, contentBlocker: ContentBlocker? = nil) -> BrowserModel {
        // Compatibility arguments never import state into an independent private window.
        BrowserModel(websiteDataStore: .nonPersistent())
    }

    var isPrivate: Bool {
        !websiteDataStore.isPersistent
    }

    /// A configuration for one of the window's pages. Pop-ups get theirs from WebKit, copied from the opener's,
    /// so they keep its data store.
    func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = BrowserTab.makeConfiguration()
        configuration.websiteDataStore = websiteDataStore
        if passwords != nil {
            PasswordAutofill.install(in: configuration.userContentController,
                                     handler: PasswordMessageHandler(browser: self))
        }
        return configuration
    }

    var activeTab: BrowserTab? {
        tab(withID: activeTabID)
    }

    var canReopenClosedTab: Bool {
        !closedTabs.isEmpty
    }

    func tab(withID id: UUID?) -> BrowserTab? {
        guard let id else { return nil }
        return tabs.first { $0.id == id }
    }

    private func makeTab(configuration: WKWebViewConfiguration? = nil) -> BrowserTab {
        adopt(BrowserTab(configuration: configuration ?? makeConfiguration(), appearance: appearance))
    }

    private func adopt(_ tab: BrowserTab) -> BrowserTab {
        tab.browser = self
        if let controller = tab.webView?.configuration.userContentController { contentBlocker.attach(controller) }
        if !isPrivate { tab.favicon = favicons.cachedIcon(for: tab.url) }
        return tab
    }

    /// A closed window must release every WebKit view before its profile can be deleted.
    func setWorkspaceActive(_ active: Bool) {
        isActiveInWorkspace = active
        if active { activeTab?.didBecomeSelected() }
    }

    func releaseClosedWindow() {
        isActiveInWorkspace = false
        tabs.forEach { $0.close() }
        activeTabID = nil
        tabs = []
        closedTabs = []
        // SwiftUI may retain a closed window model. Release its persistent store too.
        websiteDataStore = .nonPersistent()
        window = nil
    }

    func addTab() {
        let tab = makeTab()
        tabs.append(tab)
        activeTabID = tab.id
        requestAddressFocus()
    }

    /// Reuse an empty tab when possible; Home never discards the current page or its history.
    func goHome() {
        if let home = tabs.first(where: \.isNewTab) {
            activeTabID = home.id
        } else {
            addTab()
        }
        activeTab?.showsHomePage = true
        requestAddressFocus()
    }

    func duplicateTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let original = tabs[index]
        // The copy starts suspended, so selecting it restores the original's history and scroll position.
        let tab = original.url == nil ? makeTab()
            : adopt(BrowserTab(url: original.url, title: original.pageTitle, interactionState: original.interactionState, appearance: appearance))
        tabs.insert(tab, at: index + 1)
        activeTabID = tab.id
    }

    func moveTab(_ id: UUID, to destinationIndex: Int) {
        guard let sourceIndex = tabs.firstIndex(where: { $0.id == id }),
              tabs.indices.contains(destinationIndex),
              sourceIndex != destinationIndex else { return }
        tabs.move(fromOffsets: IndexSet(integer: sourceIndex),
                  toOffset: destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex)
    }

    func closeOtherTabs(than id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        for tab in tabs where tab.id != id {
            rememberClosedTab(tab)
        }
        tabs.removeAll { $0.id != id }
        activeTabID = id
    }

    func closeTabs(after id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closingTabs = tabs[(index + 1)...]
        closingTabs.forEach(rememberClosedTab)
        let closingIDs = Set(closingTabs.map(\.id))
        tabs.removeAll { closingIDs.contains($0.id) }
        if let activeTabID, closingIDs.contains(activeTabID) {
            self.activeTabID = id
        }
    }

    func closeActiveTab() {
        guard let activeTabID else { return }
        closeTab(activeTabID)
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        rememberClosedTab(tabs[index])
        tabs.remove(at: index)
        if tabs.isEmpty {
            addTab()
        } else if activeTabID == id {
            activeTabID = tabs[min(index, tabs.count - 1)].id
        }
    }

    /// Remembers a closing tab so it can reopen, and dismisses the panels its page is waiting to show.
    private func rememberClosedTab(_ tab: BrowserTab) {
        tab.cancelPendingPageWork()
        let isBlank = tab.isNewTab || tab.url == nil
        closedTabs.append(ClosedTab(url: isBlank ? nil : tab.url, title: tab.pageTitle,
                                    interactionState: isBlank ? nil : tab.interactionState))
        if closedTabs.count > 10 { closedTabs.removeFirst() }
    }

    func reopenClosedTab() {
        guard let closedTab = closedTabs.popLast() else { return }
        guard closedTab.url != nil else {
            addTab()
            return
        }
        // Selecting the suspended tab restores its history, or loads its address.
        let tab = adopt(BrowserTab(url: closedTab.url, title: closedTab.title,
                                   interactionState: closedTab.interactionState, appearance: appearance))
        tabs.append(tab)
        activeTabID = tab.id
    }

    /// Opens a tab after the opener and any tabs it opened before, like a page's pop-up or a ⌘-clicked link.
    /// Pass WebKit's configuration for a pop-up, or a request to load.
    @discardableResult
    func openChildTab(of opener: BrowserTab, configuration: WKWebViewConfiguration? = nil,
                      loading request: URLRequest? = nil, select: Bool) -> BrowserTab {
        let tab = makeTab(configuration: configuration)
        tab.isNewTab = false
        tab.openerID = opener.id
        tab.isPopUp = configuration != nil
        // Background tabs lay out at the size they'll be shown at.
        tab.contentView.frame = opener.contentView.frame
        var index = (tabs.firstIndex { $0.id == opener.id } ?? tabs.count - 1) + 1
        while tabs.indices.contains(index), tabs[index].openerID == opener.id {
            index += 1
        }
        tabs.insert(tab, at: index)
        if let request { tab.webView?.load(request) }
        if select { activeTabID = tab.id }
        return tab
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeTabID = tabs[index].id
    }

    func selectLastTab() {
        guard !tabs.isEmpty else { return }
        selectTab(at: tabs.count - 1)
    }

    func switchTab(by offset: Int) {
        guard let currentIndex = tabs.firstIndex(where: { $0.id == activeTabID }),
              !tabs.isEmpty else { return }
        selectTab(at: (currentIndex + offset + tabs.count) % tabs.count)
    }

    func open(_ url: URL, inNewTab: Bool = false) {
        if inNewTab || activeTab == nil {
            let tab = makeTab()
            tabs.append(tab)
            activeTabID = tab.id
        }
        activeTab?.load(url)
    }

    /// Opens links from other apps in new tabs, using the window's only tab if it's a new tab.
    func openInNewTabs(_ urls: [URL]) {
        for url in urls {
            open(url, inNewTab: !isBlank)
        }
    }

    func navigate(to input: String) {
        guard let url = BrowserAddress.url(for: input, searchEngine: preferences.searchEngine) else { return }
        activeTab?.load(url)
    }

    func reload() {
        guard let activeTabID else { return }
        reloadTab(activeTabID)
    }

    func reloadTab(_ id: UUID) {
        guard let tab = tab(withID: id), !tab.isNewTab else { return }
        tab.reload()
    }

    func stopLoading() {
        activeTab?.webView?.stopLoading()
    }

    func goBack() {
        activeTab?.goBack()
    }

    func goForward() {
        activeTab?.webView?.goForward()
    }

    func go(to item: WKBackForwardListItem) {
        activeTab?.webView?.go(to: item)
    }

    func requestAddressFocus() {
        addressFocusRequest += 1
    }

    /// Whether the window only has a new tab, so a restored session can take its place.
    var isBlank: Bool {
        tabs.count == 1 && tabs[0].isNewTab
    }

    func windowSession() -> WindowSession {
        WindowSession(tabs: tabs.map { tab in
            let isBlank = tab.isNewTab || tab.url == nil
            return TabSession(url: isBlank ? nil : tab.url, title: tab.pageTitle,
                              interactionState: isBlank ? nil : tab.interactionState as? Data)
        }, selectedIndex: tabs.firstIndex { $0.id == activeTabID } ?? 0)
    }

    /// Replaces the window's tabs with a saved window's. They start suspended, so only the selected tab loads.
    func restoreSession(_ session: WindowSession) {
        guard !session.tabs.isEmpty else { return }
        tabs.forEach { $0.cancelPendingPageWork() }
        tabs = session.tabs.map { tab in
            tab.url == nil ? makeTab()
                : adopt(BrowserTab(url: tab.url, title: tab.title, interactionState: tab.interactionState, appearance: appearance))
        }
        activeTabID = tabs[min(max(session.selectedIndex, 0), tabs.count - 1)].id
    }

    // MARK: Find

    /// Shows the find bar, starting with the text last searched for in any app.
    func showFindBar() {
        guard let tab = activeTab, !tab.isNewTab else { return }
        if !isPrivate, tab.findText.isEmpty, let text = NSPasteboard(name: .find).string(forType: .string) {
            tab.findText = text
        }
        tab.isFindBarVisible = true
        findFocusRequest += 1
    }

    func findNext(backwards: Bool = false) {
        guard let tab = activeTab, !tab.isNewTab else { return }
        guard !tab.findText.isEmpty else { return showFindBar() }
        tab.isFindBarVisible = true
        tab.find(backwards: backwards)
    }

    func useSelectionForFind() {
        guard let tab = activeTab, !tab.isNewTab else { return }
        Task {
            guard let text = await tab.selectedText(), !text.isEmpty else { return }
            if !isPrivate {
                let pasteboard = NSPasteboard(name: .find)
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
            tab.findText = text
            tab.isFindBarVisible = true
            tab.find()
        }
    }

    func closeFindBar() {
        guard let tab = activeTab else { return }
        tab.isFindBarVisible = false
        tab.focusPage()
    }

    // MARK: Zoom

    var canZoom: Bool {
        activeTab.map { !$0.isNewTab && !$0.isSuspended } ?? false
    }

    func zoomIn() {
        guard canZoom, let tab = activeTab else { return }
        tab.setZoom(ZoomStore.level(after: tab.pageZoom))
    }

    func zoomOut() {
        guard canZoom, let tab = activeTab else { return }
        tab.setZoom(ZoomStore.level(before: tab.pageZoom))
    }

    func resetZoom() {
        guard canZoom else { return }
        activeTab?.setZoom(1)
    }

    // MARK: Print

    /// Prints the active page, with the print panel as a sheet on its window.
    func printActivePage() {
        guard let tab = activeTab, !tab.isNewTab, let webView = tab.webView, let window = webView.window else { return }
        let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        // WebKit prints blank pages unless the operation's view has a size.
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    #if DEBUG
    func showWebInspector() {
        guard let tab = activeTab, !tab.isNewTab, let webView = tab.webView else { return }
        WebInspector.show(for: webView)
    }
    #endif

    /// Background tabs that can be suspended to free memory, least recently used first. A pop-up and its opener
    /// can script each other, so neither is suspended while both are open.
    var suspendableTabs: [BrowserTab] {
        var linkedIDs = Set<UUID>()
        for tab in tabs where tab.isPopUp {
            guard let openerID = tab.openerID, self.tab(withID: openerID) != nil else { continue }
            linkedIDs.formUnion([tab.id, openerID])
        }
        return tabs
            .filter { $0.id != activeTabID && $0.canSuspend && !linkedIDs.contains($0.id) }
            .sorted { $0.lastActive < $1.lastActive }
    }

    /// Suspends the tabs in order, except pages playing media. Each is checked again after asking WebKit about
    /// media, since it might have been selected in the meantime.
    func suspendTabs(_ candidates: [BrowserTab]) async {
        for tab in candidates {
            guard !(await tab.isPlayingMedia()), suspendableTabs.contains(where: { $0 === tab }) else { continue }
            tab.suspend()
        }
    }
}

enum BrowserAddress {
    static func url(for input: String, searchEngine: SearchEngine = .current) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let url = URL(string: text),
           ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
           url.host() != nil {
            return url
        }

        if !text.contains(where: \.isWhitespace),
           (text.contains(".") || text == "localhost"),
           let url = URL(string: "https://\(text)"),
           url.host() != nil {
            return url
        }

        return searchEngine.searchURL(for: text)
    }
}
