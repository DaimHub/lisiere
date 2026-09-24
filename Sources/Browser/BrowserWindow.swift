import SwiftUI
import WebKit

struct BrowserWindow: View {
    let bookmarks: BookmarkStore
    let library: GeneratedViewLibrary
    @State private var browser = BrowserModel()
    @State private var studio: StudioSession
    @State private var address = ""
    @State private var hoverCardTabID: UUID?
    @State private var isFullScreen = false
    @FocusState private var addressIsFocused: Bool
    @AppStorage(BookmarksBarVisibility.storageKey) private var bookmarksBarVisibility = BookmarksBarVisibility.always
    @AppStorage(TabLayout.storageKey) private var tabLayout = TabLayout.horizontal
    @AppStorage(BrowserModel.studioVisibilityKey) private var studioIsVisible = false

    private let accent = Color(red: 0.38, green: 0.49, blue: 0.54)

    init(bookmarks: BookmarkStore, library: GeneratedViewLibrary) {
        self.bookmarks = bookmarks
        self.library = library
        _studio = State(initialValue: StudioSession(library: library))
    }

    var body: some View {
        // The main column keeps one identity across layouts. Rebuilding it would briefly show the
        // active page in two WebViews at once, which WebKit treats as a fatal error.
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
        .animation(.easeOut(duration: 0.18), value: bookmarksBarVisibility)
        .animation(.easeOut(duration: 0.18), value: browser.activeTab?.isNewTab)
        .animation(.snappy(duration: 0.25), value: tabLayout)
        .animation(.snappy(duration: 0.25), value: studioIsVisible)
        .onChange(of: tabLayout) { _, _ in hoverCardTabID = nil }
        .background(WindowGlassBackground())
        .background(WindowChromeConfigurator(titlebarHeight: BrowserChrome.titlebarHeight(for: tabLayout),
                                             isFullScreen: $isFullScreen))
        .ignoresSafeArea(.container, edges: .top)
        .tint(accent)
        .focusedSceneValue(\.browserModel, browser)
        .onChange(of: browser.activeTabID) { _, _ in
            address = browser.activeTab?.page.url?.absoluteString ?? ""
        }
        .onChange(of: browser.addressFocusRequest) { _, _ in
            addressIsFocused = true
        }
        .onAppear {
            if browser.activeTab?.isNewTab == true {
                addressIsFocused = true
            }
        }
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

            // The page keeps its place in the hierarchy when the Studio pane opens or closes.
            HStack(spacing: BrowserChrome.edgeInset) {
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
                }

                if studioIsVisible {
                    StudioPane(session: studio) { studioIsVisible = false }
                        .frame(width: StudioPane.width)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.leading, leadingInset)
            .padding([.trailing, .bottom], BrowserChrome.edgeInset)
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
        WebView(tab.page)
            .webViewBackForwardNavigationGestures(.enabled)
            .webViewLinkPreviews(.enabled)
            .webViewTextSelection(.enabled)
            .webViewMagnificationGestures(.enabled)
            .webViewElementFullscreenBehavior(.enabled)
            .id(tab.id)
            .onGeometryChange(for: CGSize.self, of: \.size) { tab.viewportSize = $0 }
            .onChange(of: tab.page.isLoading) { _, isLoading in
                guard !isLoading else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    await tab.captureThumbnail()
                }
            }
            .overlay(alignment: .topLeading) {
                if tab.page.isLoading {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(accent.opacity(0.5))
                            .frame(width: max(18, geometry.size.width * tab.page.estimatedProgress),
                                   height: 2)
                    }
                    .frame(height: 2)
                    .padding(.horizontal, 12)
                    .padding(.top, 3)
                    .animation(.easeOut(duration: 0.18), value: tab.page.estimatedProgress)
                }
            }
            .onChange(of: tab.page.url) { _, url in
                if !addressIsFocused { address = url?.absoluteString ?? "" }
            }
            .onAppear {
                if !addressIsFocused { address = tab.page.url?.absoluteString ?? "" }
            }
    }

    private var navigationBar: some View {
        let page = browser.activeTab?.page

        return HStack(spacing: 6) {
            HStack(spacing: 0) {
                Button { browser.goBack() } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(page?.backForwardList.backList.isEmpty ?? true)
                .help("Back (⌘[)")
                .contextMenu {
                    historyMenu(for: Array((page?.backForwardList.backList ?? []).reversed()))
                }

                Button { browser.goForward() } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(page?.backForwardList.forwardList.isEmpty ?? true)
                .help("Forward (⌘])")
                .contextMenu {
                    historyMenu(for: page?.backForwardList.forwardList ?? [])
                }

                Button {
                    if page?.isLoading == true { page?.stopLoading() } else { browser.reload() }
                } label: {
                    Image(systemName: page?.isLoading == true ? "xmark" : "arrow.clockwise")
                        .contentTransition(.symbolEffect(.replace))
                }
                .disabled(browser.activeTab?.isNewTab ?? true)
                .help(page?.isLoading == true ? "Stop Loading" : "Reload (⌘R)")
            }
            .buttonStyle(ChromeIconButtonStyle(size: 30))
            .padding(2)
            .background(Color.primary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 7) {
                Image(systemName: browser.activeTab?.isSecure == true ? "lock.fill" : "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                TextField("Search or enter address", text: $address)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($addressIsFocused)
                    .onSubmit {
                        browser.navigate(to: address)
                        addressIsFocused = false
                    }
                    .accessibilityLabel("Address and search")
                bookmarkButton
            }
            .padding(.leading, 11)
            .padding(.trailing, 4)
            .frame(height: 34)
            .background(Color.primary.opacity(0.065),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(addressIsFocused ? accent.opacity(0.7) : Color.clear, lineWidth: 1)
            }

            Button { studioIsVisible.toggle() } label: {
                Image(systemName: "sparkles")
                    .foregroundStyle(studioIsVisible ? Color.accentColor : Color.primary)
            }
            .buttonStyle(ChromeIconButtonStyle(size: 34))
            .help(studioIsVisible ? "Hide Studio (⌘\\)" : "Show Studio (⌘\\)")
            .accessibilityLabel(studioIsVisible ? "Hide Studio" : "Show Studio")
        }
        .padding(.trailing, BrowserChrome.edgeInset)
        .frame(height: BrowserChrome.navigationBarHeight)
    }

    @ViewBuilder
    private var bookmarkButton: some View {
        if let tab = browser.activeTab, !tab.isNewTab, let url = tab.page.url {
            let isBookmarked = bookmarks.isBookmarked(url)
            Button { bookmarks.toggle(title: tab.page.title, url: url) } label: {
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
    private func historyMenu(for items: [WebPage.BackForwardList.Item]) -> some View {
        ForEach(items.prefix(15)) { item in
            Button(item.title.flatMap { $0.isEmpty ? nil : $0 } ?? item.url.absoluteString) {
                browser.go(to: item)
            }
        }
    }
}
