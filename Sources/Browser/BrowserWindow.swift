import SwiftUI
import WebKit

struct BrowserWindow: View {
    @State private var browser = BrowserModel()
    @State private var address = ""
    @State private var hoveredTabID: UUID?
    @FocusState private var addressIsFocused: Bool

    private let accent = Color(red: 0.38, green: 0.49, blue: 0.54)

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                tabStrip
                navigationBar
            }

            if let tab = browser.activeTab {
                Group {
                    if tab.isNewTab {
                        NewTabView { browser.requestAddressFocus() }
                    } else {
                        webView(for: tab)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .padding(8)
            }
        }
        .background(WindowGlassBackground())
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

    private func webView(for tab: BrowserTab) -> some View {
        WebView(tab.page)
            .webViewBackForwardNavigationGestures(.enabled)
            .webViewLinkPreviews(.enabled)
            .webViewTextSelection(.enabled)
            .webViewMagnificationGestures(.enabled)
            .webViewElementFullscreenBehavior(.enabled)
            .id(tab.id)
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

    private var tabStrip: some View {
        GeometryReader { geometry in
            let tabWidth = CGFloat(browser.tabs.count) * 190
                + CGFloat(max(browser.tabs.count - 1, 0)) * 6
            let availableWidth = max(190, geometry.size.width - 180)

            HStack(spacing: 8) {
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(browser.tabs) { tab in
                                tabButton(for: tab)
                                    .id(tab.id)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: browser.tabs.count) { _, _ in
                        if let activeTabID = browser.activeTabID {
                            scrollProxy.scrollTo(activeTabID, anchor: .trailing)
                        }
                    }
                }
                .frame(width: min(tabWidth, availableWidth))

                Button { browser.addTab() } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(ChromeIconButtonStyle())
                .help("New Tab (⌘T)")
                .accessibilityLabel("New Tab")

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
            }
            .padding(.leading, 80)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 34)
    }

    private func tabButton(for tab: BrowserTab) -> some View {
        let isActive = browser.activeTabID == tab.id
        let isHovered = hoveredTabID == tab.id

        return HStack(spacing: 4) {
            Button { browser.activeTabID = tab.id } label: {
                HStack(spacing: 8) {
                    Group {
                        if let favicon = tab.favicon {
                            favicon
                                .resizable()
                                .scaledToFit()
                        } else {
                            Image(systemName: "globe")
                                .resizable()
                                .scaledToFit()
                        }
                    }
                    .frame(width: 14, height: 14)
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    Text(tab.title)
                        .font(.system(size: 13, weight: .medium))
                        .tracking(-0.15)
                        .foregroundStyle(isActive ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isActive ? .isSelected : [])
            Button { browser.closeTab(tab.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ChromeCloseButtonStyle())
            .help("Close Tab")
            .accessibilityLabel("Close \(tab.title)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(width: 190, height: 34)
        .background(isActive ? Color.primary.opacity(0.10) :
                    isHovered ? Color.primary.opacity(0.05) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isActive ? Color.primary.opacity(0.08) : Color.clear, lineWidth: 1)
        }
        .onHover { hoveredTabID = $0 ? tab.id : nil }
        .task(id: tab.page.url) {
            await tab.updateFavicon()
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                Button { browser.goBack() } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(browser.activeTab?.page.backForwardList.backList.isEmpty ?? true)
                .help("Back (⌘[)")

                Button { browser.goForward() } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(browser.activeTab?.page.backForwardList.forwardList.isEmpty ?? true)
                .help("Forward (⌘])")

                Button { browser.reload() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(browser.activeTab?.isNewTab ?? true)
                .help("Reload (⌘R)")
            }
            .buttonStyle(ChromeIconButtonStyle())
            .padding(3)
            .background(Color.primary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search or enter address", text: $address)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($addressIsFocused)
                    .onSubmit {
                        browser.navigate(to: address)
                        addressIsFocused = false
                    }
                    .accessibilityLabel("Address and search")
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color.primary.opacity(0.065),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(addressIsFocused ? accent.opacity(0.7) : Color.clear, lineWidth: 1)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }
}

private struct ChromeIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.5))
            .frame(width: 32, height: 32)
            .background(!isEnabled ? Color.clear :
                        configuration.isPressed ? Color.primary.opacity(0.12) :
                        isHovered ? Color.primary.opacity(0.07) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

private struct ChromeCloseButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovered ? Color.primary : Color.secondary)
            .background(configuration.isPressed ? Color.primary.opacity(0.12) :
                        isHovered ? Color.primary.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { isHovered = $0 }
    }
}
