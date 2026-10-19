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

    private(set) var tabs: [BrowserTab] = [] {
        didSet {
            updateSelectedPages()
            reconcileSplitView()
        }
    }
    private(set) var groups: [TabGroup] = []

    /// Window-local pairing survives selection of other tabs; both pages keep their own WebKit state.
    private(set) var splitTabIDs: [UUID] = [] {
        didSet { updateSelectedPages() }
    }
    var hasSplitPair: Bool { splitTabIDs.count == 2 }
    var isSplitView: Bool { hasSplitPair && splitTabIDs.contains { $0 == activeTabID } }
    /// Page consumers observe selection identity, not the tab strip's changing order.
    private(set) var activeTab: BrowserTab?
    private(set) var splitTabs: [BrowserTab] = []
    var splitDividerFraction: CGFloat = 0.5

    struct TabStripGroup: Identifiable {
        let id: UUID
        let tabs: [BrowserTab]
    }

    /// Keep the pair joined even while another tab is visible. The card mirrors left/right pane order.
    var tabStripGroups: [TabStripGroup] {
        // A split across pin/group boundaries keeps separate cards in their proper sections.
        let pair = splitTabs
        let joinsPair = pair.count == 2 && pair[0].isPinned == pair[1].isPinned && pair[0].groupID == pair[1].groupID
        let anchor = tabs.first { splitTabIDs.contains($0.id) }?.id
        return tabs.compactMap { tab in
            if joinsPair, splitTabIDs.contains(tab.id) {
                return tab.id == anchor ? TabStripGroup(id: tab.id, tabs: splitTabs) : nil
            }
            return TabStripGroup(id: tab.id, tabs: [tab])
        }
    }

    func isTabVisible(_ id: UUID) -> Bool {
        id == activeTabID || (isSplitView && splitTabIDs.contains(id))
    }

    /// Uses only this model's tabs, so pages never cross profile or private-window data stores.
    func startSplitView(with id: UUID? = nil) {
        guard let first = activeTab else { return }
        let second: BrowserTab
        if let id {
            guard id != first.id, let existing = tab(withID: id) else { return }
            second = existing
        } else {
            second = makeTab()
            second.groupID = first.groupID
            tabs.append(second)
            normalizeTabOrder()
        }
        let pair = [first.id, second.id]
        if splitTabIDs != pair { splitDividerFraction = 0.5 }
        splitTabIDs = pair
        first.restore()
        second.restore()
        activeTabID = second.id
        if second.isNewTab { requestAddressFocus() }
    }

    /// A page drop replaces only the chosen pane. The displaced tab stays open.
    func canSplitTab(_ id: UUID) -> Bool {
        tab(withID: id) != nil && activeTab != nil && (id != activeTabID || isSplitView)
    }

    func splitTab(_ id: UUID, on side: TabSplitSide) {
        guard canSplitTab(id), let dragged = tab(withID: id) else { return }
        let partnerID = isSplitView
            ? (splitTabIDs.contains(id) ? splitTabIDs.first { $0 != id } : splitTabIDs[side == .leading ? 1 : 0])
            : activeTabID
        guard let partnerID, let partner = tab(withID: partnerID), partnerID != id else { return }
        let pair = side == .leading ? [id, partnerID] : [partnerID, id]
        if Set(pair) != Set(splitTabIDs) { splitDividerFraction = 0.5 }
        splitTabIDs = pair
        partner.restore()
        dragged.restore()
        activeTabID = id
        if dragged.isNewTab { requestAddressFocus() }
    }

    /// Moves the live page only after a compatible destination exists. Never records a closed tab.
    @discardableResult
    func moveTab(_ id: UUID, to destination: BrowserModel) -> Bool {
        guard destination !== self, destination.isActiveInWorkspace, isActiveInWorkspace,
              profileID == destination.profileID, isPrivate == destination.isPrivate,
              websiteDataStore === destination.websiteDataStore ||
                (!isPrivate && websiteDataStore.identifier == destination.websiteDataStore.identifier),
              let index = tabs.firstIndex(where: { $0.id == id }), tabs[index].canMoveBetweenWindows,
              destination.tab(withID: id) == nil else { return false }
        let tab = tabs[index]
        let blank = destination.isBlank ? destination.tabs.first : nil
        if let groupID = tab.groupID, let group = groups.first(where: { $0.id == groupID }),
           !destination.groups.contains(where: { $0.id == groupID }) {
            destination.groups.append(group)
        }
        tabs.remove(at: index)
        if tabs.isEmpty { addTab() }
        else if activeTabID == id { activeTabID = tabs[min(index, tabs.count - 1)].id }
        if let blank, !blank.isPinned, blank.groupID == nil {
            blank.close()
            destination.tabs = []
        }
        tab.openerID = nil
        destination.tabs.append(destination.adopt(tab))
        destination.normalizeTabOrder()
        destination.activeTabID = id
        return true
    }

    /// Exiting split view never closes either page or discards form input/history.
    func endSplitView(keeping id: UUID? = nil) {
        let keptID = id.flatMap { splitTabIDs.contains($0) ? $0 : nil } ?? activeTabID
        splitTabIDs = []
        activeTabID = keptID
    }

    func focusOtherSplitPane() {
        guard isSplitView, let id = splitTabIDs.first(where: { $0 != activeTabID }) else { return }
        activeTabID = id
        if activeTab?.isNewTab == true { requestAddressFocus() }
        else { activeTab?.focusPage() }
    }

    private func reconcileSplitView() {
        guard hasSplitPair, splitTabIDs.contains(where: { tab(withID: $0) == nil }) else { return }
        let survivor = splitTabIDs.first { tab(withID: $0) != nil }
        splitTabIDs = []
        if activeTab == nil, let survivor { activeTabID = survivor }
    }
    private var closedTabs: [ClosedTab] = []
    @ObservationIgnored private var isRestoringSession = false
    var activeTabID: UUID? {
        didSet {
            guard oldValue != activeTabID else { return }
            updateSelectedPages()
            if let previousTab = tab(withID: oldValue) {
                // Keep a preview of the page being left for background-tab hover cards.
                previousTab.captureThumbnail(afterScreenUpdates: false)
                previousTab.lastActive = .now
            }
            if !isRestoringSession { expandGroup(activeTab?.groupID) }
            // Returning to either member must also restore a partner suspended while the pair was parked.
            if isSplitView { splitTabs.forEach { $0.restore() } }
            else { activeTab?.restore() }
            activeTab?.didBecomeSelected()
            if isSplitView { activeTab?.focusPage() }
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
        let groupID: UUID?
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

    /// Keep these projections synchronous with mutations. A drop can reorder the array twice;
    /// unchanged page identities must not invalidate the toolbar, page host and their layout graph.
    private func updateSelectedPages() {
        let selected = tab(withID: activeTabID)
        if activeTab !== selected { activeTab = selected }
        let panes = splitTabIDs.compactMap { tab(withID: $0) }
        if panes.count != splitTabs.count || !zip(panes, splitTabs).allSatisfy({ $0 === $1 }) {
            splitTabs = panes
        }
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
        groups = []
        // SwiftUI may retain a closed window model. Release its persistent store too.
        websiteDataStore = .nonPersistent()
        window = nil
    }

    func addTab(in groupID: UUID? = nil) {
        let tab = makeTab()
        tab.groupID = validGroupID(groupID)
        expandGroup(tab.groupID)
        tabs.append(tab)
        normalizeTabOrder()
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
        tab.groupID = original.groupID
        tabs.insert(tab, at: index + 1)
        normalizeTabOrder()
        activeTabID = tab.id
    }

    func moveTab(_ id: UUID, to destinationIndex: Int) {
        guard let sourceIndex = tabs.firstIndex(where: { $0.id == id }),
              tabs.indices.contains(destinationIndex),
              sourceIndex != destinationIndex,
              tabs[sourceIndex].isPinned == tabs[destinationIndex].isPinned,
              tabs[sourceIndex].groupID == tabs[destinationIndex].groupID else { return }
        tabs.move(fromOffsets: IndexSet(integer: sourceIndex),
                  toOffset: destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex)
    }

    /// A joined split card moves as a unit, even when its tabs were originally non-adjacent.
    func moveTabGroup(containing id: UUID, beside targetID: UUID) {
        let groups = tabStripGroups
        guard let source = groups.first(where: { $0.tabs.contains { $0.id == id } }),
              let target = groups.first(where: { $0.tabs.contains { $0.id == targetID } }),
              source.id != target.id,
              source.tabs.first?.isPinned == target.tabs.first?.isPinned,
              source.tabs.first?.groupID == target.tabs.first?.groupID else { return }
        let sourceIDs = Set(source.tabs.map(\.id))
        let targetIDs = Set(target.tabs.map(\.id))
        let offsets = IndexSet(tabs.indices.filter { sourceIDs.contains(tabs[$0].id) })
        let destinations = tabs.indices.filter { targetIDs.contains(tabs[$0].id) }
        guard let first = offsets.first, let targetFirst = destinations.first,
              let targetLast = destinations.last else { return }
        tabs.move(fromOffsets: offsets, toOffset: first < targetFirst ? targetLast + 1 : targetFirst)
    }

    /// Drops commit once, after the pointer is released. Hovering or cancelling never changes membership.
    func canDropTab(_ id: UUID, beside targetID: UUID) -> Bool {
        guard let source = tab(withID: id), let target = tab(withID: targetID),
              id != targetID, source.isPinned == target.isPinned else { return false }
        return !tabStripGroups.contains { card in
            card.tabs.contains { $0.id == id } && card.tabs.contains { $0.id == targetID }
        }
    }

    func dropTab(_ id: UUID, beside targetID: UUID, after: Bool) {
        guard canDropTab(id, beside: targetID),
              let source = tabStripGroups.first(where: { $0.tabs.contains { $0.id == id } }),
              let target = tabStripGroups.first(where: { $0.tabs.contains { $0.id == targetID } }),
              let targetTab = target.tabs.first else { return }
        let movingIDs = Set(source.tabs.map(\.id))
        let targetIDs = Set(target.tabs.map(\.id))
        var ordered = tabs.filter { !movingIDs.contains($0.id) }
        let indices = ordered.indices.filter { targetIDs.contains(ordered[$0].id) }
        guard let first = indices.first, let last = indices.last else { return }
        source.tabs.forEach { $0.groupID = targetTab.groupID }
        ordered.insert(contentsOf: source.tabs, at: after ? last + 1 : first)
        tabs = ordered
        expandGroup(targetTab.groupID)
        normalizeTabOrder()
    }

    /// A group header also accepts pinned tabs and empty/collapsed groups, without unpinning or loading pages.
    func dropTab(_ id: UUID, into groupID: UUID?) {
        guard groupID == nil || validGroupID(groupID) != nil,
              let source = tabStripGroups.first(where: { $0.tabs.contains { $0.id == id } }) else { return }
        let movingIDs = Set(source.tabs.map(\.id))
        source.tabs.forEach { $0.groupID = groupID }
        tabs = tabs.filter { !movingIDs.contains($0.id) } + source.tabs
        expandGroup(groupID)
        normalizeTabOrder()
    }

    func closeOtherTabs(than id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        for tab in tabs where tab.id != id && !tab.isPinned {
            rememberClosedTab(tab)
        }
        tabs.removeAll { $0.id != id && !$0.isPinned }
        activeTabID = id
    }

    func closeTabs(after id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closingTabs = tabs[(index + 1)...].filter { !$0.isPinned }
        closingTabs.forEach(rememberClosedTab)
        let closingIDs = Set(closingTabs.map(\.id))
        tabs.removeAll { closingIDs.contains($0.id) }
        if let activeTabID, closingIDs.contains(activeTabID) {
            self.activeTabID = id
        }
    }

    /// Context-menu ordering follows the visible cards, including a non-adjacent split pair.
    func closeTabs(afterGroupContaining id: UUID) {
        let groups = tabStripGroups
        guard let index = groups.firstIndex(where: { $0.tabs.contains { $0.id == id } }) else { return }
        let closingIDs = Set(groups.dropFirst(index + 1).flatMap { $0.tabs.filter { !$0.isPinned }.map(\.id) })
        for tab in tabs where closingIDs.contains(tab.id) { rememberClosedTab(tab) }
        tabs.removeAll { closingIDs.contains($0.id) }
        if let activeTabID, closingIDs.contains(activeTabID) { self.activeTabID = id }
    }

    func closeActiveTab() {
        guard let activeTabID else { return }
        closeTab(activeTabID)
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), !tabs[index].isPinned else { return }
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
                                    interactionState: isBlank ? nil : tab.interactionState, groupID: tab.groupID))
        if closedTabs.count > 10 { closedTabs.removeFirst() }
    }

    func reopenClosedTab() {
        guard let closedTab = closedTabs.popLast() else { return }
        guard closedTab.url != nil else {
            addTab(in: closedTab.groupID)
            return
        }
        // Selecting the suspended tab restores its history, or loads its address.
        let tab = adopt(BrowserTab(url: closedTab.url, title: closedTab.title,
                                   interactionState: closedTab.interactionState, appearance: appearance))
        tab.groupID = validGroupID(closedTab.groupID)
        tabs.append(tab)
        normalizeTabOrder()
        activeTabID = tab.id
    }

    /// Opens a tab after the opener and any tabs it opened before, like a page's pop-up or a ⌘-clicked link.
    /// Pass WebKit's configuration for a pop-up, or a request to load.
    @discardableResult
    func openChildTab(of opener: BrowserTab, configuration: WKWebViewConfiguration? = nil,
                      loading request: URLRequest? = nil, select: Bool) -> BrowserTab {
        let tab = makeTab(configuration: configuration)
        tab.isNewTab = false
        tab.groupID = opener.groupID
        tab.openerID = opener.id
        tab.isPopUp = configuration != nil
        // Background tabs lay out at the size they'll be shown at.
        tab.contentView.frame = opener.contentView.frame
        var index = (tabs.firstIndex { $0.id == opener.id } ?? tabs.count - 1) + 1
        while tabs.indices.contains(index), tabs[index].openerID == opener.id {
            index += 1
        }
        tabs.insert(tab, at: index)
        normalizeTabOrder()
        if let request { tab.webView?.load(request) }
        if select { activeTabID = tab.id }
        return tab
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        expandGroup(tabs[index].groupID)
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

    // MARK: Pins and named groups

    func setPinned(_ pinned: Bool, for id: UUID) {
        guard let tab = tab(withID: id), tab.isPinned != pinned else { return }
        tab.isPinned = pinned
        if pinned { tab.restorePinnedFavicon() }
        normalizeTabOrder()
    }

    @discardableResult
    func createGroup(name: String, color: TabGroupColor, tabID: UUID? = nil) -> UUID {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = TabGroup(name: name.isEmpty ? "New Group" : name, color: color)
        groups.append(group)
        if let tabID { assignTab(tabID, to: group.id) }
        return group.id
    }

    func updateGroup(_ id: UUID, name: String, color: TabGroupColor) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = name
        groups[index].color = color
    }

    func assignTab(_ id: UUID, to groupID: UUID?) {
        guard let tab = tab(withID: id), groupID == nil || validGroupID(groupID) != nil else { return }
        tab.groupID = groupID
        expandGroup(groupID)
        normalizeTabOrder()
    }

    /// Removing a folder keeps its pages, pins, WebKit state, and selection intact.
    func ungroup(_ id: UUID) {
        for tab in tabs where tab.groupID == id { tab.groupID = nil }
        groups.removeAll { $0.id == id }
        normalizeTabOrder()
    }

    func toggleGroupCollapsed(_ id: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].isCollapsed.toggle()
    }

    func moveGroup(_ id: UUID, by offset: Int) {
        guard let index = groups.firstIndex(where: { $0.id == id }),
              groups.indices.contains(index + offset) else { return }
        groups.swapAt(index, index + offset)
        normalizeTabOrder()
    }

    /// Reorder a folder as one unit without changing membership, collapse state or page identity.
    func moveGroup(_ id: UUID, beside targetID: UUID, after: Bool) {
        guard id != targetID, let group = groups.first(where: { $0.id == id }),
              groups.contains(where: { $0.id == targetID }) else { return }
        var ordered = groups.filter { $0.id != id }
        guard let target = ordered.firstIndex(where: { $0.id == targetID }) else { return }
        ordered.insert(group, at: target + (after ? 1 : 0))
        guard ordered != groups else { return }
        groups = ordered
        normalizeTabOrder()
    }

    func moveGroupToEnd(_ id: UUID) {
        guard let lastID = groups.last?.id else { return }
        moveGroup(id, beside: lastID, after: true)
    }

    private func validGroupID(_ id: UUID?) -> UUID? {
        id.flatMap { id in groups.contains { $0.id == id } ? id : nil }
    }

    func expandGroup(_ id: UUID?) {
        guard let id, let index = groups.firstIndex(where: { $0.id == id }), groups[index].isCollapsed else { return }
        groups[index].isCollapsed = false
    }

    func collapseGroup(_ id: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == id }), !groups[index].isCollapsed else { return }
        groups[index].isCollapsed = true
    }

    /// Stable linear partition: pins lead; each named group stays contiguous within each pin section.
    private func normalizeTabOrder() {
        let pinned = Dictionary(grouping: tabs.filter(\.isPinned), by: \.groupID)
        let regular = Dictionary(grouping: tabs.filter { !$0.isPinned }, by: \.groupID)
        var ordered: [BrowserTab] = pinned[nil] ?? []
        for group in groups { ordered += pinned[group.id] ?? [] }
        for group in groups { ordered += regular[group.id] ?? [] }
        ordered += regular[nil] ?? []
        if ordered.map(\.id) != tabs.map(\.id) { tabs = ordered }
    }

    struct TabSection: Identifiable {
        let group: TabGroup?
        let isPinned: Bool
        let cards: [TabStripGroup]
        var id: String { "\(isPinned)-\(group?.id.uuidString ?? "ungrouped")" }
        var tabCount: Int { cards.reduce(0) { $0 + $1.tabs.count } }
        var visibleCards: [TabStripGroup] { group?.isCollapsed == true ? [] : cards }
    }

    /// Build the section lookup once, independent of page loading and favicon updates.
    var tabSections: [TabSection] {
        let cards = tabStripGroups
        let pinned = Dictionary(grouping: cards.filter { $0.tabs.first?.isPinned == true }, by: { $0.tabs.first?.groupID })
        let regular = Dictionary(grouping: cards.filter { $0.tabs.first?.isPinned != true }, by: { $0.tabs.first?.groupID })
        var sections: [TabSection] = []
        if let loose = pinned[nil] { sections.append(TabSection(group: nil, isPinned: true, cards: loose)) }
        for group in groups {
            if let items = pinned[group.id] { sections.append(TabSection(group: group, isPinned: true, cards: items)) }
        }
        for group in groups {
            if let items = regular[group.id] {
                sections.append(TabSection(group: group, isPinned: false, cards: items))
            } else if pinned[group.id] == nil {
                sections.append(TabSection(group: group, isPinned: false, cards: []))
            }
        }
        if let loose = regular[nil] { sections.append(TabSection(group: nil, isPinned: false, cards: loose)) }
        return sections
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
        tabs.count == 1 && tabs[0].isNewTab && !tabs[0].isPinned && groups.isEmpty
    }

    func windowSession() -> WindowSession {
        WindowSession(tabs: tabs.map { tab in
            let isBlank = tab.isNewTab || tab.url == nil
            return TabSession(url: isBlank ? nil : tab.url, title: tab.pageTitle,
                              interactionState: isBlank ? nil : tab.interactionState as? Data,
                              isPinned: tab.isPinned, groupID: tab.groupID)
        }, selectedIndex: tabs.firstIndex { $0.id == activeTabID } ?? 0, groups: groups)
    }

    /// Replaces the window's tabs with a saved window's. They start suspended, so only the selected tab loads.
    func restoreSession(_ session: WindowSession) {
        guard !session.tabs.isEmpty else { return }
        isRestoringSession = true
        defer { isRestoringSession = false }
        tabs.forEach { $0.cancelPendingPageWork() }
        var seen = Set<UUID>()
        groups = session.groups.filter { seen.insert($0.id).inserted }
        tabs = session.tabs.map { saved in
            let tab = saved.url == nil ? makeTab()
                : adopt(BrowserTab(url: saved.url, title: saved.title, interactionState: saved.interactionState, appearance: appearance))
            tab.isPinned = saved.isPinned
            tab.restorePinnedFavicon()
            tab.groupID = validGroupID(saved.groupID)
            return tab
        }
        let selectedID = tabs[min(max(session.selectedIndex, 0), tabs.count - 1)].id
        normalizeTabOrder()
        activeTabID = selectedID
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
            .filter { !isTabVisible($0.id) && $0.canSuspend && !linkedIDs.contains($0.id) }
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
