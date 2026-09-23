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
            navigationBar

            if let tab = browser.activeTab {
                WebView(tab.page)
                    .webViewBackForwardNavigationGestures(.enabled)
                    .webViewLinkPreviews(.enabled)
                    .webViewTextSelection(.enabled)
                    .webViewMagnificationGestures(.enabled)
                    .webViewElementFullscreenBehavior(.enabled)
                    .id(tab.id)
                    .overlay(alignment: .top) {
                        if tab.page.isLoading {
                            ProgressView(value: tab.page.estimatedProgress)
                                .progressViewStyle(.linear)
                                .tint(accent)
                        }
                    }
                    .onChange(of: tab.page.url) { _, url in
                        if !addressIsFocused { address = url?.absoluteString ?? "" }
                    }
                    .onAppear {
                        if !addressIsFocused { address = tab.page.url?.absoluteString ?? "" }
                    }
            }
        }
        .background(.windowBackground)
        .tint(accent)
        .toolbar {
            ToolbarItem(placement: .principal) {
                tabStrip
            }
        }
        .focusedSceneValue(\.browserModel, browser)
        .onChange(of: browser.activeTabID) { _, _ in
            address = browser.activeTab?.page.url?.absoluteString ?? ""
        }
        .onChange(of: browser.addressFocusRequest) { _, _ in
            addressIsFocused = true
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(browser.tabs) { tab in
                        tabButton(for: tab)
                    }
                }
            }
            .scrollIndicators(.hidden)

            Button { browser.addTab() } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(ChromeIconButtonStyle())
            .help("New Tab (⌘T)")
            .accessibilityLabel("New Tab")
        }
        .frame(minWidth: 240, idealWidth: 640, maxWidth: 900, maxHeight: 36)
    }

    private func tabButton(for tab: BrowserTab) -> some View {
        let isActive = browser.activeTabID == tab.id
        let isHovered = hoveredTabID == tab.id

        return HStack(spacing: 4) {
            Button { browser.activeTabID = tab.id } label: {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 12, weight: .medium))
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
    }

    private var navigationBar: some View {
        HStack(spacing: 12) {
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
        .frame(height: 50)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Color.primary.opacity(0.07).frame(height: 1)
        }
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
