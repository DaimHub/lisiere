import SwiftUI
import WebKit

private struct AddressBarFrameKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct BrowserWindow: View {
    let profiles: ProfileStore
    let profileID: UUID?
    let bookmarks: BookmarkStore
    @Bindable private var browser: BrowserModel
    @State private var address = ""
    /// What the user typed, without the inline completion.
    @State private var typedAddress = ""
    @State private var completionStart: Int?
    @State private var suggestions: [AddressSuggestion] = []
    @State private var suggestionSearch = AddressSuggestionSearch()
    @State private var suggestionTask: Task<Void, Never>?
    @State private var suggestionRequest = 0
    @State private var queuedAddressCommands: [AddressField.Command] = []
    @State private var selectedSuggestion: Int?
    @State private var addressBlurRequest = 0
    @State private var hoverCardTabID: UUID?
    @State private var tabDrag = TabDragController()
    let isFullScreen: Bool
    @State private var addressIsFocused = false
    @State private var toolbarWidth: CGFloat = 800
    @State private var isShowingDownloads = false
    @State private var isCustomizingToolbar = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(BrowsingData.self) private var browsingData
    private var bookmarksBarVisibility: BookmarksBarVisibility { browser.preferences.bookmarksBarVisibility }
    private var tabLayout: TabLayout { browser.preferences.tabLayout }
    private var contentBlocker: ContentBlocker { browser.contentBlocker }

    private var accent: Color {
        if browser.isPrivate {
            return colorScheme == .dark
                ? Color(red: 0.70, green: 0.62, blue: 0.96)
                : Color(red: 0.35, green: 0.25, blue: 0.60)
        }
        return browser.preferences.accentColor
    }

    init(bookmarks: BookmarkStore, profiles: ProfileStore,
         browser: BrowserModel, isFullScreen: Bool) {
        self.bookmarks = bookmarks
        self.profiles = profiles
        self.profileID = browser.profileID
        self.isFullScreen = isFullScreen
        self.browser = browser
    }

    var body: some View {
        // The main column keeps one identity across layouts, so switching layouts doesn't rebuild the page host.
        HStack(spacing: 0) {
            if tabLayout == .vertical {
                TabStrip(browser: browser, layout: .vertical, isFullScreen: isFullScreen, accent: accent,
                         hoverCardTabID: $hoverCardTabID, drag: tabDrag, ownsDragSpace: false)
                    .background(profileSwipeArea)
                    .frame(width: BrowserChrome.sidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            VStack(spacing: 0) {
                if tabLayout == .horizontal {
                    TabStrip(browser: browser, layout: .horizontal, isFullScreen: isFullScreen, accent: accent,
                             hoverCardTabID: $hoverCardTabID, drag: tabDrag, ownsDragSpace: false)
                        .background(profileSwipeArea)
                        .transition(.opacity)
                }
                WindowSection { mainColumn }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !browser.isPrivate, let profileID, let context = profiles.context(for: profileID),
               let failure = context.persistenceFailure {
                HStack(spacing: 12) {
                    Text(failure.message).font(.callout).fixedSize(horizontal: false, vertical: true)
                    if failure.canRetry { Button("Retry") { context.retryPersistence() } }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
                .accessibilityIdentifier("persistence-error")
            }
        }
        .coordinateSpace(name: TabDragController.coordinateSpace)
        .background(TabDragCoordinates(drag: tabDrag, browser: browser))
        .overlayPreferenceValue(TabDragBoundsKey.self) { bounds in
            TabDragGeometryObserver(bounds: bounds, includesWindow: true, drag: tabDrag, browser: browser)
        }
        .overlay { TabDragPreview(drag: tabDrag, browser: browser) }
        .overlayPreferenceValue(TabFrameKey.self) { tabFrames in
            hoverCard(tabFrames: tabFrames)
        }
        .overlayPreferenceValue(AddressBarFrameKey.self) { anchor in
            suggestionList(below: anchor)
        }
        .animation(.easeOut(duration: 0.18), value: bookmarksBarVisibility)
        .modifier(PageSelectionAnimation(browser: browser))
        .animation(.snappy(duration: 0.25), value: tabLayout)
        .onChange(of: tabLayout) { _, _ in hoverCardTabID = nil }
        .background {
            if browser.isPrivate {
                BrowserChrome.privateTint(for: colorScheme).ignoresSafeArea()
            } else if let tint = browser.appearance.interfaceColor.tint(
                for: colorScheme, customColor: browser.appearance.customInterfaceColor) {
                Color(nsColor: tint).ignoresSafeArea()
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .tint(accent)
        .modifier(WorkspaceActivity(browser: browser) { active in
            if active {
                if browser.activeTab?.isNewTab == true { browser.requestAddressFocus() }
                else { browser.activeTab?.focusPage() }
            } else {
                if !suggestions.isEmpty || suggestionTask != nil { closeSuggestions() }
                hoverCardTabID = nil
                addressIsFocused = false
                isShowingDownloads = false
                isCustomizingToolbar = false
                if tabDrag.isDragging { tabDrag.reset() }
            }
        })
        .modifier(TabSelectionObserver(browser: browser) {
            address = browser.activeTab?.url?.absoluteString ?? ""
            closeSuggestions()
        })
        .onChange(of: addressIsFocused) { _, isFocused in
            guard !isFocused else { return }
            // A click on a suggestion takes focus first, so the list stays a moment for the click to land.
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                if !addressIsFocused { closeSuggestions() }
            }
        }
        .sheet(isPresented: $browser.isShowingClearData) {
            ClearDataView(data: browsingData, profileName: profileID.map(profiles.name) ?? "Private")
        }
        .sheet(isPresented: $browser.isShowingHistory) {
            if let history = browser.history {
                HistoryView(history: history) { url, inNewTab in
                    browser.isShowingHistory = false
                    browser.open(url, inNewTab: inNewTab)
                }
            }
        }
        .task(id: addressIsFocused) {
            guard addressIsFocused else { return }
            await suggestionSearch.prepare(visits: browser.history?.visits ?? [],
                                           revision: browser.history?.revision ?? 0, bookmarks: bookmarks.bookmarks)
        }
        .onDisappear { closeSuggestions(); tabDrag.reset(); tabDrag.detachTab = nil }
        .onAppear {
            tabDrag.detachTab = { id, point in
                guard let token = TabWindowTransfer.prepare(tabID: id, source: browser, at: point) else { return }
                openWindow(id: browser.isPrivate ? BrowserApp.privateWindowID : BrowserApp.windowID,
                           value: ProfileWindowRequest(profileID: browser.profileID ?? BrowserProfile.initialID,
                                                       tabTransferID: token))
            }
            if browser.activeTab?.isNewTab == true {
                browser.requestAddressFocus()
            }
        }
    }

    private var profileSwipeArea: some View {
        ProfileSwipeArea(enabled: !browser.isPrivate && profiles.availableProfiles.count > 1,
                         isWorkspaceActive: { browser.isActiveInWorkspace }) { direction in
            hoverCardTabID = nil
            browser.profileWindow?.switchBy(direction)
        }
    }

    @ViewBuilder
    private func suggestionList(below anchor: Anchor<CGRect>?) -> some View {
        if let anchor, !suggestions.isEmpty {
            GeometryReader { geometry in
                let frame = geometry[anchor]
                AddressSuggestionList(suggestions: suggestions, selectedIndex: selectedSuggestion) { suggestion in
                    open(suggestion)
                }
                .frame(width: frame.width)
                .offset(x: frame.minX, y: frame.maxY + 4)
            }
            .transition(.opacity)
        }
    }

    // MARK: Address bar

    private func editAddress(_ edit: AddressField.Edit) {
        let text = edit.text
        // Typing more of the text completes it again; deleting doesn't, so the deleted completion stays gone.
        let isAppending = text.count > typedAddress.count && text.hasPrefix(typedAddress)
        typedAddress = text
        selectedSuggestion = nil
        completionStart = nil
        suggestionTask?.cancel()
        suggestionRequest += 1
        let request = suggestionRequest
        queuedAddressCommands = []
        let visits = browser.history?.visits ?? []
        let revision = browser.history?.revision ?? 0
        let bookmarks = bookmarks.bookmarks
        suggestionTask = Task {
            let result = await suggestionSearch.rank(text, visits: visits, revision: revision, bookmarks: bookmarks)
            guard !Task.isCancelled, request == suggestionRequest else { return }
            suggestions = result
            if isAppending, edit.canComplete(), let completion = AddressSuggestions.inlineCompletion(of: text, with: result.first) {
                completionStart = (text as NSString).length
                address = completion
            } else {
                completionStart = nil
            }
            suggestionTask = nil
            let commands = queuedAddressCommands
            queuedAddressCommands = []
            for command in commands {
                guard request == suggestionRequest else { break }
                _ = performAddressCommand(command)
            }
        }
    }

    private func performAddressCommand(_ command: AddressField.Command) -> Bool {
        // Commands must use the latest text's results, never the preceding keystroke's suggestions.
        if suggestionTask != nil {
            queuedAddressCommands.append(command)
            return true
        }
        switch command {
        case .moveDown, .moveUp:
            guard !suggestions.isEmpty else { return false }
            let offset = command == .moveDown ? 1 : -1
            let index = (selectedSuggestion ?? -1) + offset
            completionStart = nil
            if index < 0 {
                selectedSuggestion = nil
                address = typedAddress
            } else {
                selectedSuggestion = min(index, suggestions.count - 1)
                address = suggestions[min(index, suggestions.count - 1)].url.absoluteString
            }
            return true
        case .submit:
            if let selectedSuggestion, suggestions.indices.contains(selectedSuggestion) {
                open(suggestions[selectedSuggestion])
            } else {
                browser.navigate(to: address)
                finishEditingAddress()
            }
            return true
        case .cancel:
            if suggestions.isEmpty {
                address = browser.activeTab?.url?.absoluteString ?? ""
                typedAddress = address
            } else {
                address = typedAddress
                closeSuggestions()
            }
            completionStart = nil
            return true
        }
    }

    private func open(_ suggestion: AddressSuggestion) {
        // The list can report a click more than once before it closes.
        guard !suggestions.isEmpty else { return }
        suggestionTask?.cancel()
        suggestionTask = nil
        suggestionRequest += 1
        address = suggestion.url.absoluteString
        browser.open(suggestion.url)
        finishEditingAddress()
    }

    private func finishEditingAddress() {
        closeSuggestions()
        completionStart = nil
        addressBlurRequest += 1
    }

    private func closeSuggestions() {
        suggestionTask?.cancel()
        suggestionTask = nil
        suggestionRequest += 1
        queuedAddressCommands = []
        suggestions = []
        selectedSuggestion = nil
        typedAddress = ""
    }

    /// Navigation, bookmarks, and the page. In the vertical layout the sidebar supplies the leading inset.
    private var mainColumn: some View {
        let leadingInset = tabLayout == .vertical ? 0 : BrowserChrome.edgeInset

        return VStack(spacing: 0) {
            WindowSection { navigationBar }
                .padding(.leading, leadingInset)

            if !browser.isPrivate, bookmarksBarVisibility.isVisible(onNewTab: browser.activeTab?.isNewTab ?? true) {
                BookmarksBar(bookmarks: bookmarks, browser: browser)
                    .padding(.leading, leadingInset - BrowserChrome.edgeInset)
                    .padding(.bottom, 4)
                    .transition(.opacity)
            }

            Group {
                if browser.isSplitView {
                    HSplitView {
                        ForEach(browser.splitTabs) { tab in
                            splitPane(for: tab)
                                .frame(minWidth: 180, maxWidth: .infinity, maxHeight: .infinity)
                                .background {
                                    if tab.id == browser.splitTabIDs.first {
                                        SplitDividerPosition(browser: browser)
                                    }
                                }
                        }
                    }
                } else if let tab = browser.activeTab {
                    page(for: tab)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .transformAnchorPreference(key: TabDragBoundsKey.self, value: .bounds) { value, anchor in
                value.page = anchor
            }
            .overlay { TabPageDropPreview(drag: tabDrag, accent: accent) }
            .padding(.leading, leadingInset)
            .padding([.trailing, .bottom], BrowserChrome.edgeInset)
        }
    }

    private func page(for tab: BrowserTab) -> some View {
        BrowserPage(bookmarks: bookmarks, browser: browser, tab: tab, accent: accent,
                    focusAddress: {
                        browser.activeTabID = tab.id
                        browser.requestAddressFocus()
                    }, updateAddress: { url in
                        if browser.activeTabID == tab.id, !addressIsFocused { address = url?.absoluteString ?? "" }
                    })
    }

    private func splitPane(for tab: BrowserTab) -> some View {
        let isActive = browser.activeTabID == tab.id
        let isLeading = browser.splitTabIDs.first == tab.id
        // Match the page container at the outside corners; keep the shared divider straight.
        let shape = UnevenRoundedRectangle(topLeadingRadius: isLeading ? 12 : 0,
                                           bottomLeadingRadius: isLeading ? 12 : 0,
                                           bottomTrailingRadius: isLeading ? 0 : 12,
                                           topTrailingRadius: isLeading ? 0 : 12)
        return VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    browser.activeTabID = tab.id
                    if tab.isNewTab { browser.requestAddressFocus() } else { tab.focusPage() }
                } label: {
                    HStack(spacing: 6) {
                        Image(browserIcon: isActive ? .checkmarkCircle : .circle, size: 12)
                        Text(tab.title).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(isActive ? "Active" : "Activate") pane: \(tab.title)")
                Button {
                    browser.endSplitView(keeping: browser.splitTabIDs.first { $0 != tab.id })
                } label: {
                    Image(browserIcon: .close, size: 11)
                }
                .buttonStyle(ChromeIconButtonStyle(size: 24))
                .help("Remove from Split View (keeps tab open)")
                .accessibilityLabel("Remove \(tab.title) from Split View")
            }
            .font(.system(size: 11, weight: isActive ? .medium : .regular))
            .foregroundStyle(isActive ? accent : .secondary)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(isActive ? accent.opacity(0.09) : Color.primary.opacity(0.035))
            page(for: tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SplitPaneActivation {
            guard browser.isActiveInWorkspace, browser.isTabVisible(tab.id) else { return }
            browser.activeTabID = tab.id
        })
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(isActive ? accent.opacity(0.65) : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
    }

    private func hoverCard(tabFrames: [UUID: Anchor<CGRect>]) -> some View {
        GeometryReader { geometry in
            if let tab = browser.tab(withID: hoverCardTabID), let anchor = tabFrames[tab.id] {
                let tabFrame = geometry[anchor]
                let position = tabLayout == .vertical
                    // Beside the sidebar row, kept clear of the window's bottom edge.
                    ? CGPoint(x: tabFrame.maxX + 10,
                              y: max(BrowserChrome.edgeInset, min(tabFrame.minY - 4, geometry.size.height - 250)))
                    : CGPoint(x: min(max(tabFrame.minX, BrowserChrome.edgeInset),
                                     geometry.size.width - TabHoverCard.width - BrowserChrome.edgeInset),
                              y: tabFrame.maxY + 6)
                TabHoverCard(tab: tab, isActive: tab.id == browser.activeTabID)
                    .offset(x: position.x, y: position.y)
                    .transition(tabLayout == .vertical ? .opacity.combined(with: .offset(x: -3))
                                                       : .opacity.combined(with: .offset(y: -3)))
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.14), value: hoverCardTabID)
    }



    private var navigationBar: some View {
        let verticalInset = BrowserChrome.navigationBarVerticalInset(for: tabLayout)
        let presentation = browser.preferences.toolbarLayout.presentation(
            width: toolbarWidth, hasDownloads: !browser.downloads.items.isEmpty, isPrivate: browser.isPrivate)
        return HStack(spacing: 6) {
            ForEach(presentation.visible) { entry in
                toolbarEntry(entry, compactProfile: presentation.compactProfile)
            }
            if !presentation.overflow.isEmpty,
               !presentation.visible.contains(where: { $0.items.contains(.allActions) }) {
                allActionsMenu.toolbarControlBackground()
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { toolbarWidth = $0 }
        .padding(.trailing, BrowserChrome.edgeInset)
        .frame(height: BrowserChrome.navigationControlHeight)
        .padding(.top, tabLayout == .vertical ? verticalInset : 0)
        .padding(.bottom, verticalInset)
        .popover(isPresented: $isShowingDownloads) { DownloadsList(downloads: browser.downloads) }
        .sheet(isPresented: $isCustomizingToolbar) { ToolbarSettings(preferences: browser.preferences) }
    }

    @ViewBuilder
    private func toolbarEntry(_ entry: ToolbarEntry, compactProfile: Bool) -> some View {
        if entry.items.count == 1, let item = entry.items.first, item == .profile || item == .address {
            toolbarControl(item, compactProfile: compactProfile, grouped: false)
        } else {
            HStack(spacing: 0) {
                ForEach(entry.items) { item in
                    toolbarControl(item, compactProfile: compactProfile, grouped: true)
                }
            }
            .toolbarControlBackground()
            .frame(maxWidth: entry.items.contains(.address) ? .infinity : nil)
        }
    }

    @ViewBuilder
    private func toolbarControl(_ item: BrowserToolbarItem, compactProfile: Bool, grouped: Bool) -> some View {
        switch item {
        case .profile:
            if browser.isPrivate { privateLabel(grouped: grouped) } else { profileMenu(compact: compactProfile) }
        case .address: addressControl(grouped: grouped).frame(minWidth: 160, maxWidth: .infinity)
        case .downloads: DownloadsButton(downloads: browser.downloads, controlSize: 30)
        case .allActions: allActionsMenu
        default:
            actionButton(item)
                .browserContextMenu {
                    if item == .back { return historyMenu(for: Array((browser.activeTab?.backList ?? []).reversed())) }
                    if item == .forward { return historyMenu(for: browser.activeTab?.forwardList ?? []) }
                    return []
                }
        }
    }

    private func actionButton(_ item: BrowserToolbarItem) -> some View {
        Button { performToolbarAction(item) } label: {
            Image(browserIcon: actionIcon(item))
                .contentTransition(.opacity)
        }
        .buttonStyle(ChromeIconButtonStyle(size: 30))
        .disabled(toolbarActionDisabled(item))
        .help(actionHelp(item))
        .accessibilityLabel(actionTitle(item))
    }

    private func actionTitle(_ item: BrowserToolbarItem) -> String {
        item == .reload && browser.activeTab?.isLoading == true ? "Stop Loading" : item.title
    }
    private func actionHelp(_ item: BrowserToolbarItem) -> String {
        switch item {
        case .back: "Back (⌘[)"
        case .forward: "Forward (⌘])"
        case .reload: browser.activeTab?.isLoading == true ? "Stop Loading" : "Reload (⌘R)"
        case .newTab: "New Tab (⌘T)"
        default: item.title
        }
    }
    private func actionIcon(_ item: BrowserToolbarItem) -> BrowserIcon {
        item == .reload && browser.activeTab?.isLoading == true ? .close : item.icon
    }
    private func toolbarActionDisabled(_ item: BrowserToolbarItem) -> Bool {
        switch item {
        case .back: !(browser.activeTab?.canNavigateBack ?? false)
        case .forward: !(browser.activeTab?.canGoForward ?? false)
        case .reload: browser.activeTab?.isNewTab ?? true
        case .history, .bookmarks: browser.isPrivate
        default: false
        }
    }

    private func performToolbarAction(_ item: BrowserToolbarItem) {
        switch item {
        case .back: browser.goBack()
        case .forward: browser.goForward()
        case .reload:
            if browser.activeTab?.isLoading == true { browser.stopLoading() } else { browser.reload() }
        case .address: browser.requestAddressFocus()
        case .newTab: browser.addTab()
        case .home: browser.goHome()
        case .privateWindow: openWindow(id: BrowserApp.privateWindowID)
        case .history: browser.isShowingHistory = true
        case .downloads: isShowingDownloads = true
        case .bookmarks:
            browser.preferences.bookmarksBarVisibility = bookmarksBarVisibility == .never ? .always : .never
        case .settings: openSettings()
        default: break
        }
    }

    private var allActionsMenu: some View {
        Menu { BrowserMenuContent(actions: allActions) } label: {
            Image(browserIcon: .more)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(ChromeIconButtonStyle(size: 30))
        .help("All Actions")
        .accessibilityLabel("All Actions")
        .browserMenu { allActions }
    }

    private var allActions: [BrowserContextAction] {
        var actions: [BrowserContextAction] = [browser.isPrivate
            ? .init(title: "Private Window", icon: .privateWindow, isEnabled: false)
            : .init(title: "Profiles", icon: .profile, children: profileActions)]
        for group: [BrowserToolbarItem] in [[.back, .forward, .reload, .address], [.newTab, .home, .privateWindow], [.history, .downloads, .bookmarks, .settings]] {
            actions += group.map { item in
                .init(title: actionTitle(item), icon: actionIcon(item), isEnabled: !toolbarActionDisabled(item)) {
                    performToolbarAction(item)
                }
            }
            actions.append(.separator)
        }
        actions += [.init(title: "Split View", icon: .splitView, children: browser.splitViewActions), .separator]
        actions.append(.init(title: "Customize Toolbar…", icon: .sliders) { isCustomizingToolbar = true })
        return actions
    }

    private var profileActions: [BrowserContextAction] {
        var actions: [BrowserContextAction] = [.init(title: "Profile: \(profileID.map(profiles.name) ?? "Private")", icon: nil, isEnabled: false)]
        actions += profiles.availableProfiles.map { profile in
            .init(title: profile.name, icon: profile.icon.browserIcon) { profiles.activate(profile.id, in: browser, openWindow: openWindow) }
        }
        actions += [.separator, .init(title: "Manage Profiles…", icon: .profiles) {
            profiles.settingsTab = .profiles
            openSettings()
        }]
        return actions
    }

    private func profileMenu(compact: Bool) -> some View {
        ToolbarProfileMenu(name: profileID.map(profiles.name) ?? "Private",
                           icon: profileID.flatMap(profiles.profile)?.icon.browserIcon ?? .profile,
                           compact: compact, accent: accent) {
            BrowserMenuContent(actions: profileActions)
        }
        .browserMenu { profileActions }
    }

    private func addressControl(grouped: Bool) -> some View {
        HStack(spacing: 7) {
            Image(browserIcon: browser.activeTab?.isSecure == true ? .secure : .search, size: 11)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            AddressField(text: $address, isFocused: $addressIsFocused, completionStart: completionStart,
                         focusRequest: browser.addressFocusRequest, blurRequest: addressBlurRequest,
                         edit: editAddress, perform: performAddressCommand)
            zoomButton
            passwordButton
            trackerBlockingButton
            bookmarkButton
        }
        .padding(.leading, 11)
        .padding(.trailing, 4)
        .frame(height: grouped ? 30 : BrowserChrome.navigationControlHeight)
        .background(Color.primary.opacity(grouped ? 0 : 0.065),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(addressIsFocused ? accent : .clear, lineWidth: 2)
        }
        .anchorPreference(key: AddressBarFrameKey.self, value: .bounds) { $0 }
    }

    @ViewBuilder
    private var zoomButton: some View {
        if let tab = browser.activeTab, !tab.isNewTab, tab.pageZoom != 1 {
            Button { browser.resetZoom() } label: {
                Text(tab.pageZoom, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Reset Zoom (⌘0)")
            .accessibilityLabel("Zoom \(Int((tab.pageZoom * 100).rounded())) percent, reset")
        }
    }

    private func privateLabel(grouped: Bool) -> some View {
        Label("Private", browserIcon: .privateWindow)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(accent)
            .padding(.horizontal, 10)
            .frame(height: grouped ? 30 : BrowserChrome.navigationControlHeight)
            .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .help("Private Window: history is not saved; cookies and website data are removed when all windows in this session close")
            .accessibilityLabel("Private Window")
    }

    /// Shows whether trackers are blocked on the page's site, and turns blocking off for the site. A private window
    /// shows the state without changing it, since the change would be kept after it closes.
    @ViewBuilder
    private var trackerBlockingButton: some View {
        if contentBlocker.isEnabled, let tab = browser.activeTab, !tab.isNewTab, let host = tab.host,
           ["http", "https"].contains(tab.url?.scheme?.lowercased() ?? "") {
            let isBlocking = contentBlocker.isBlocking(on: host)
            let wantsBlocking = contentBlocker.wantsBlocking(on: host)
            let statusText = contentBlocker.statusText(on: host)
            Menu {
                Text(statusText)
                Button(wantsBlocking ? "Turn Off Blocking for This Site" : "Turn On Blocking for This Site",
                       browserIcon: isBlocking ? .shieldOff : .shield) {
                    Task {
                        await contentBlocker.setBlocking(!wantsBlocking, on: host)
                        tab.reload()
                    }
                }
                .disabled(browser.isPrivate)
            } label: {
                Image(browserIcon: isBlocking ? .shield : .shieldOff)
                    .foregroundStyle(isBlocking ? Color.secondary : Color.orange)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(ChromeIconButtonStyle(size: 26))
            .fixedSize()
            .help(statusText)
            .accessibilityLabel(statusText)
            .browserMenu {
                [.init(title: statusText, icon: nil, isEnabled: false),
                 .init(title: wantsBlocking ? "Turn Off Blocking for This Site" : "Turn On Blocking for This Site",
                       icon: isBlocking ? .shieldOff : .shield, isEnabled: !browser.isPrivate) {
                     Task {
                         await contentBlocker.setBlocking(!wantsBlocking, on: host)
                         tab.reload()
                     }
                 }]
            }
        }
    }

    /// Offers the passwords saved for exactly the page's origin, once the page shows a password field.
    @ViewBuilder
    private var passwordButton: some View {
        if let tab = browser.activeTab, !tab.isNewTab, tab.hasPasswordFields, let passwords = browser.passwords {
            let accounts = passwords.passwords(for: PasswordOrigin(url: tab.url))
            if !accounts.isEmpty {
                Menu {
                    ForEach(accounts) { account in
                        Button(account.username.isEmpty ? "Fill Password" : "Fill “\(account.username)”", browserIcon: .key) {
                            Task { await PasswordAutofill.fill(account, in: tab, from: passwords) }
                        }
                    }
                    Divider()
                    Button("Show Passwords…", browserIcon: .key) { openSettings() }
                } label: {
                    Image(browserIcon: .key)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(ChromeIconButtonStyle(size: 26))
                .fixedSize()
                .help("Fill Saved Password")
                .accessibilityLabel("Fill saved password")
                .browserMenu {
                    var actions: [BrowserContextAction] = accounts.map { account in
                        .init(title: account.username.isEmpty ? "Fill Password" : "Fill “\(account.username)”", icon: .key) {
                            Task { await PasswordAutofill.fill(account, in: tab, from: passwords) }
                        }
                    }
                    actions += [.separator, .init(title: "Show Passwords…", icon: .key) { openSettings() }]
                    return actions
                }
            }
        }
    }

    @ViewBuilder
    private var bookmarkButton: some View {
        if !browser.isPrivate, let tab = browser.activeTab, !tab.isNewTab, let url = tab.url {
            let isBookmarked = bookmarks.isBookmarked(url)
            Button { bookmarks.toggle(title: tab.pageTitle, url: url) } label: {
                Image(browserIcon: isBookmarked ? .bookmarkSelected : .bookmark)
                    .foregroundStyle(isBookmarked ? Color.yellow : Color.secondary)
                    .contentTransition(.opacity)
            }
            .buttonStyle(ChromeIconButtonStyle(size: 26))
            .help(isBookmarked ? "Remove Bookmark (⌘D)" : "Bookmark This Page (⌘D)")
            .accessibilityLabel(isBookmarked ? "Remove Bookmark" : "Bookmark This Page")
        }
    }

    private func historyMenu(for items: [WKBackForwardListItem]) -> [BrowserContextAction] {
        items.prefix(15).map { item in
            .init(title: item.title.flatMap { $0.isEmpty ? nil : $0 } ?? item.url.absoluteString, icon: .history) {
                browser.go(to: item)
            }
        }
    }
}

/// Isolate workspace activation from the expensive toolbar/page body. A departing profile stays
/// visible during the fade, but its native controls must not receive pointer or accessibility input.
struct WorkspaceActivity: ViewModifier {
    let browser: BrowserModel
    let changed: (Bool) -> Void
    func body(content: Content) -> some View {
        content
            .allowsHitTesting(browser.isActiveInWorkspace)
            .accessibilityHidden(!browser.isActiveInWorkspace)
            .modifier(WorkspaceActivationObserver(browser: browser, changed: changed))
    }
}

/// Observing activation must not reset a parent's hit-testing or accessibility visibility.
struct WorkspaceActivationObserver: ViewModifier {
    let browser: BrowserModel
    let changed: (Bool) -> Void
    func body(content: Content) -> some View {
        content.onChange(of: browser.isActiveInWorkspace) { _, active in changed(active) }
    }
}

/// Evaluate each region in its own observation scope. Inline computed-view helpers otherwise make
/// changes to the selected page dirty the whole window, including drag geometry and unrelated chrome.
private struct WindowSection<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View { content() }
}

private struct PageSelectionAnimation: ViewModifier {
    let browser: BrowserModel
    func body(content: Content) -> some View {
        content.animation(.easeOut(duration: 0.18), value: browser.activeTab?.isNewTab)
    }
}

private struct TabSelectionObserver: ViewModifier {
    let browser: BrowserModel
    let changed: () -> Void
    func body(content: Content) -> some View {
        content.onChange(of: browser.activeTabID) { _, _ in changed() }
    }
}
