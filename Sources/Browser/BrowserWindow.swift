import SwiftUI
import WebKit

private struct AddressBarFrameKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct BrowserWindow: View {
    let bookmarks: BookmarkStore
    let session: SessionStore?
    @State private var browser: BrowserModel
    @State private var address = ""
    /// What the user typed, without the inline completion.
    @State private var typedAddress = ""
    @State private var completionStart: Int?
    @State private var suggestions: [AddressSuggestion] = []
    @State private var selectedSuggestion: Int?
    @State private var addressBlurRequest = 0
    @State private var hoverCardTabID: UUID?
    @State private var isFullScreen = false
    @State private var addressIsFocused = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(BrowsingData.self) private var browsingData
    @AppStorage(BookmarksBarVisibility.storageKey) private var bookmarksBarVisibility = BookmarksBarVisibility.always
    @AppStorage(TabLayout.storageKey) private var tabLayout = TabLayout.horizontal

    private let contentBlocker = ContentBlocker.shared

    private var accent: Color {
        if browser.isPrivate {
            return colorScheme == .dark
                ? Color(red: 0.70, green: 0.62, blue: 0.96)
                : Color(red: 0.35, green: 0.25, blue: 0.60)
        }
        return Color(red: 0.38, green: 0.49, blue: 0.54)
    }

    /// Pass `nil` for the history and session of a window whose pages aren't remembered. A private window keeps
    /// its cookies and site data apart from other windows, and only until it closes.
    init(bookmarks: BookmarkStore, downloads: DownloadManager, history: HistoryStore?, session: SessionStore?,
         isPrivate: Bool = false) {
        self.bookmarks = bookmarks
        self.session = isPrivate ? nil : session
        _browser = State(initialValue: isPrivate ? .makePrivate(downloads: downloads)
                                                 : BrowserModel(downloads: downloads, history: history,
                                                                passwords: .shared))
    }

    var body: some View {
        // The main column keeps one identity across layouts, so switching layouts doesn't rebuild the page host.
        HStack(spacing: 0) {
            if tabLayout == .vertical {
                TabStrip(browser: browser, layout: .vertical, isFullScreen: isFullScreen,
                         hoverCardTabID: $hoverCardTabID)
                    .frame(width: BrowserChrome.sidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            VStack(spacing: 0) {
                if tabLayout == .horizontal {
                    TabStrip(browser: browser, layout: .horizontal, isFullScreen: isFullScreen,
                             hoverCardTabID: $hoverCardTabID)
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
            WindowGlassBackground()
            if browser.isPrivate {
                BrowserChrome.privateTint(for: colorScheme).ignoresSafeArea()
            }
        }
        .background(WindowChromeConfigurator(titlebarHeight: BrowserChrome.titlebarHeight(for: tabLayout),
                                             isFullScreen: $isFullScreen,
                                             onWindowChange: { [browser] in browser.window = $0 }) {
            session?.detach(browser)
            ExternalURLRouter.shared.unregister(browser)
        })
        .ignoresSafeArea(.container, edges: .top)
        .tint(accent)
        .focusedSceneValue(\.browserModel, browser)
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
            ClearDataView(data: browsingData)
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
            if let session {
                for _ in 0..<session.attach(browser) {
                    openWindow(id: BrowserApp.windowID)
                }
            }
            ExternalURLRouter.shared.register(browser, openWindow: openWindow)
            if browser.activeTab?.isNewTab == true {
                browser.requestAddressFocus()
            }
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

            if bookmarksBarVisibility.isVisible(onNewTab: browser.activeTab?.isNewTab ?? true) {
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
        let tab = browser.activeTab
        let isLoading = tab?.isLoading == true

        return HStack(spacing: 6) {
            HStack(spacing: 0) {
                Button { browser.goBack() } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!(tab?.canNavigateBack ?? false))
                .help("Back (⌘[)")
                .contextMenu {
                    historyMenu(for: Array((tab?.backList ?? []).reversed()))
                }

                Button { browser.goForward() } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!(tab?.canGoForward ?? false))
                .help("Forward (⌘])")
                .contextMenu {
                    historyMenu(for: tab?.forwardList ?? [])
                }

                Button {
                    if isLoading { browser.stopLoading() } else { browser.reload() }
                } label: {
                    Image(systemName: isLoading ? "xmark" : "arrow.clockwise")
                        .contentTransition(.symbolEffect(.replace))
                }
                .disabled(tab?.isNewTab ?? true)
                .help(isLoading ? "Stop Loading" : "Reload (⌘R)")
            }
            .buttonStyle(ChromeIconButtonStyle(size: 30))
            .padding(2)
            .background(Color.primary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if browser.isPrivate {
                privateLabel
            }

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
            .frame(height: 34)
            .background(Color.primary.opacity(0.065),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(addressIsFocused ? Color(nsColor: .keyboardFocusIndicatorColor) : .clear, lineWidth: 2)
            }
            .anchorPreference(key: AddressBarFrameKey.self, value: .bounds) { $0 }

            if !browser.downloads.items.isEmpty {
                DownloadsButton(downloads: browser.downloads)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.trailing, BrowserChrome.edgeInset)
        .frame(height: BrowserChrome.navigationBarHeight)
        .animation(.snappy(duration: 0.2), value: browser.downloads.items.isEmpty)
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

    private var privateLabel: some View {
        Label("Private", systemImage: "eyeglasses")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(accent)
            .padding(.horizontal, 10)
            .frame(height: 34)
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
        if let tab = browser.activeTab, !tab.isNewTab, let url = tab.url {
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
