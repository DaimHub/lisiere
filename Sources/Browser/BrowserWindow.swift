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
    @State private var selectedSuggestion: Int?
    @State private var addressBlurRequest = 0
    @State private var hoverCardTabID: UUID?
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
                TabStrip(browser: browser, layout: .vertical, isFullScreen: isFullScreen,
                         hoverCardTabID: $hoverCardTabID)
                    .background(profileSwipeArea)
                    .frame(width: BrowserChrome.sidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            VStack(spacing: 0) {
                if tabLayout == .horizontal {
                    TabStrip(browser: browser, layout: .horizontal, isFullScreen: isFullScreen,
                             hoverCardTabID: $hoverCardTabID)
                        .background(profileSwipeArea)
                        .transition(.opacity)
                }
                mainColumn
            }
        }
        .overlayPreferenceValue(TabFrameKey.self) { tabFrames in
            hoverCard(tabFrames: tabFrames)
        }
        .overlayPreferenceValue(AddressBarFrameKey.self) { anchor in
            suggestionList(below: anchor)
        }
        .animation(.easeOut(duration: 0.18), value: bookmarksBarVisibility)
        .animation(.easeOut(duration: 0.18), value: browser.activeTab?.isNewTab)
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
        // A departing profile remains visible during its fade, but cannot receive input or commands.
        .allowsHitTesting(browser.isActiveInWorkspace)
        .accessibilityHidden(!browser.isActiveInWorkspace)
        .focusedSceneValue(\.browserModel, browser.isActiveInWorkspace ? browser : nil)
        .onChange(of: browser.activeTabID) { _, _ in
            address = browser.activeTab?.url?.absoluteString ?? ""
            closeSuggestions()
        }
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
        .onAppear {
            if browser.activeTab?.isNewTab == true {
                browser.requestAddressFocus()
            }
        }
    }

    private var profileSwipeArea: some View {
        ProfileSwipeArea(enabled: !browser.isPrivate && profiles.availableProfiles.count > 1) { direction in
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

    private func editAddress(_ text: String) {
        // Typing more of the text completes it again; deleting doesn't, so the deleted completion stays gone.
        let isAppending = text.count > typedAddress.count && text.hasPrefix(typedAddress)
        typedAddress = text
        selectedSuggestion = nil
        suggestions = AddressSuggestions.rank(text, pages: browser.history?.pages ?? [],
                                              bookmarks: bookmarks.bookmarks)
        if isAppending, let completion = AddressSuggestions.inlineCompletion(of: text, with: suggestions.first) {
            completionStart = (text as NSString).length
            address = completion
        } else {
            completionStart = nil
        }
    }

    private func performAddressCommand(_ command: AddressField.Command) -> Bool {
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
        suggestions = []
        selectedSuggestion = nil
        typedAddress = ""
    }

    /// Navigation, bookmarks, and the page. In the vertical layout the sidebar supplies the leading inset.
    private var mainColumn: some View {
        let leadingInset = tabLayout == .vertical ? 0 : BrowserChrome.edgeInset

        return VStack(spacing: 0) {
            navigationBar
                .padding(.leading, leadingInset)

            if !browser.isPrivate, bookmarksBarVisibility.isVisible(onNewTab: browser.activeTab?.isNewTab ?? true) {
                BookmarksBar(bookmarks: bookmarks, browser: browser)
                    .padding(.leading, leadingInset - BrowserChrome.edgeInset)
                    .padding(.bottom, 4)
                    .transition(.opacity)
            }

            if let tab = browser.activeTab {
                Group {
                    if tab.isNewTab {
                        NewTabView(bookmarks: bookmarks, browser: browser) { browser.requestAddressFocus() }
                    } else {
                        webView(for: tab)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .padding(.leading, leadingInset)
                .padding([.trailing, .bottom], BrowserChrome.edgeInset)
            }
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

    private func webView(for tab: BrowserTab) -> some View {
        PageHost(content: tab.contentView)
            .overlay {
                if let error = tab.loadError {
                    PageErrorView(error: error, isLoading: tab.isLoading) { tab.retry() }
                }
            }
            .overlay(alignment: .topTrailing) {
                if tab.isFindBarVisible {
                    FindBar(tab: tab, browser: browser)
                        .padding(10)
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            .animation(.easeOut(duration: 0.15), value: tab.isFindBarVisible)
            .overlay(alignment: .topLeading) {
                if tab.isLoading {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(accent.opacity(0.5))
                            .frame(width: max(18, geometry.size.width * tab.estimatedProgress),
                                   height: 2)
                    }
                    .frame(height: 2)
                    .padding(.horizontal, 12)
                    .padding(.top, 3)
                    .animation(.easeOut(duration: 0.18), value: tab.estimatedProgress)
                }
            }
            .onChange(of: tab.url) { _, url in
                if !addressIsFocused { address = url?.absoluteString ?? "" }
            }
            .onAppear {
                if !addressIsFocused { address = tab.url?.absoluteString ?? "" }
            }
    }

    private var navigationBar: some View {
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
        .frame(height: BrowserChrome.navigationBarHeight)
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
                .contextMenu {
                    if item == .back { historyMenu(for: Array((browser.activeTab?.backList ?? []).reversed())) }
                    if item == .forward { historyMenu(for: browser.activeTab?.forwardList ?? []) }
                }
        }
    }

    private func actionButton(_ item: BrowserToolbarItem) -> some View {
        Button { performToolbarAction(item) } label: {
            Image(systemName: actionSymbol(item))
                .contentTransition(.symbolEffect(.replace))
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
    private func actionSymbol(_ item: BrowserToolbarItem) -> String {
        item == .reload && browser.activeTab?.isLoading == true ? "xmark" : item.symbol
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
        Menu {
            if !browser.isPrivate {
                Menu {
                    profileMenuContents
                } label: {
                    Label("Profiles", systemImage: BrowserToolbarItem.profile.symbol)
                }
            } else {
                Label("Private Window", systemImage: "eyeglasses")
            }
            ForEach([BrowserToolbarItem.back, .forward, .reload, .address]) { menuAction($0) }
            Divider()
            ForEach([BrowserToolbarItem.newTab, .home, .privateWindow]) { menuAction($0) }
            Divider()
            ForEach([BrowserToolbarItem.history, .downloads, .bookmarks, .settings]) { menuAction($0) }
            Divider()
            Button { isCustomizingToolbar = true } label: {
                Label("Customize Toolbar…", systemImage: "slider.horizontal.3")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(ChromeIconButtonStyle(size: 30))
        .help("All Actions")
        .accessibilityLabel("All Actions")
    }

    private func menuAction(_ item: BrowserToolbarItem) -> some View {
        Button { performToolbarAction(item) } label: {
            Label(actionTitle(item), systemImage: actionSymbol(item))
        }
        .disabled(toolbarActionDisabled(item))
    }

    @ViewBuilder
    private var profileMenuContents: some View {
        Text("Profile: \(profileID.map(profiles.name) ?? "Private")")
        ForEach(profiles.availableProfiles) { profile in
            Button { profiles.activate(profile.id, in: browser, openWindow: openWindow) } label: {
                Label(profile.name, systemImage: profile.icon.rawValue)
            }
        }
        Divider()
        Button("Manage Profiles…") {
            profiles.settingsTab = .profiles
            openSettings()
        }
    }

    private func profileMenu(compact: Bool) -> some View {
        ToolbarProfileMenu(name: profileID.map(profiles.name) ?? "Private",
                           symbol: profileID.flatMap(profiles.profile)?.icon.rawValue ?? "person.crop.circle",
                           compact: compact, accent: accent) {
            profileMenuContents
        }
    }

    private func addressControl(grouped: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: browser.activeTab?.isSecure == true ? "lock.fill" : "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
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
        Label("Private", systemImage: "eyeglasses")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(accent)
            .padding(.horizontal, 10)
            .frame(height: grouped ? 30 : BrowserChrome.navigationControlHeight)
            .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .help("Private Window: history, cookies, and website data aren’t kept after it closes")
            .accessibilityLabel("Private Window")
    }

    /// Shows whether trackers are blocked on the page's site, and turns blocking off for the site. A private window
    /// shows the state without changing it, since the change would be kept after it closes.
    @ViewBuilder
    private var trackerBlockingButton: some View {
        if contentBlocker.isEnabled, let tab = browser.activeTab, !tab.isNewTab, let host = tab.host,
           ["http", "https"].contains(tab.url?.scheme?.lowercased() ?? "") {
            let isBlocking = contentBlocker.isBlocking(on: host)
            let site = ContentBlocker.site(host)
            Menu {
                Text(isBlocking ? "Trackers are blocked on \(site)" : "Tracker blocking is off for \(site)")
                Button(isBlocking ? "Turn Off Blocking for This Site" : "Turn On Blocking for This Site") {
                    Task {
                        await contentBlocker.setBlocking(!isBlocking, on: host)
                        tab.reload()
                    }
                }
                .disabled(browser.isPrivate)
            } label: {
                Image(systemName: isBlocking ? "shield.lefthalf.filled" : "shield.slash")
                    .foregroundStyle(isBlocking ? Color.secondary : Color.orange)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(ChromeIconButtonStyle(size: 26))
            .fixedSize()
            .help(isBlocking ? "Trackers Blocked" : "Tracker Blocking Off for This Site")
            .accessibilityLabel(isBlocking ? "Trackers blocked" : "Tracker blocking off")
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
                        Button(account.username.isEmpty ? "Fill Password" : "Fill “\(account.username)”") {
                            Task { await PasswordAutofill.fill(account, in: tab, from: passwords) }
                        }
                    }
                    Divider()
                    Button("Show Passwords…") { openSettings() }
                } label: {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(ChromeIconButtonStyle(size: 26))
                .fixedSize()
                .help("Fill Saved Password")
                .accessibilityLabel("Fill saved password")
            }
        }
    }

    @ViewBuilder
    private var bookmarkButton: some View {
        if !browser.isPrivate, let tab = browser.activeTab, !tab.isNewTab, let url = tab.url {
            let isBookmarked = bookmarks.isBookmarked(url)
            Button { bookmarks.toggle(title: tab.pageTitle, url: url) } label: {
                Image(systemName: isBookmarked ? "star.fill" : "star")
                    .foregroundStyle(isBookmarked ? Color.yellow : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(ChromeIconButtonStyle(size: 26))
            .help(isBookmarked ? "Remove Bookmark (⌘D)" : "Bookmark This Page (⌘D)")
            .accessibilityLabel(isBookmarked ? "Remove Bookmark" : "Bookmark This Page")
        }
    }

    @ViewBuilder
    private func historyMenu(for items: [WKBackForwardListItem]) -> some View {
        ForEach(items.prefix(15), id: \.self) { item in
            Button(item.title.flatMap { $0.isEmpty ? nil : $0 } ?? item.url.absoluteString) {
                browser.go(to: item)
            }
        }
    }
}
