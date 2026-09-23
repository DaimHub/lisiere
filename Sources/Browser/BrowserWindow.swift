import SwiftUI
import WebKit

struct BrowserWindow: View {
    @State private var browser = BrowserModel()
    @State private var address = ""
    @FocusState private var addressIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
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
                                .tint(.accentColor)
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
        .focusedSceneValue(\.browserModel, browser)
        .onChange(of: browser.activeTabID) { _, _ in
            address = browser.activeTab?.page.url?.absoluteString ?? ""
        }
        .onChange(of: browser.addressFocusRequest) { _, _ in
            addressIsFocused = true
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 5) {
            ScrollView(.horizontal) {
                HStack(spacing: 5) {
                    ForEach(browser.tabs) { tab in
                        tabButton(for: tab)
                    }
                }
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.hidden)

            Button { browser.addTab() } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("New Tab (⌘T)")
            .accessibilityLabel("New Tab")
            .padding(.trailing, 12)
        }
        .frame(height: 39)
        .background(.bar)
    }

    private func tabButton(for tab: BrowserTab) -> some View {
        let isActive = browser.activeTabID == tab.id

        return HStack(spacing: 3) {
            Button { browser.activeTabID = tab.id } label: {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundStyle(.secondary)
                    Text(tab.title)
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
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Close Tab")
            .accessibilityLabel("Close \(tab.title)")
        }
        .padding(.horizontal, 10)
        .frame(width: 190, height: 30)
        .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
    }

    private var navigationBar: some View {
        HStack(spacing: 10) {
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

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search or enter address", text: $address)
                    .textFieldStyle(.plain)
                    .focused($addressIsFocused)
                    .onSubmit {
                        browser.navigate(to: address)
                        addressIsFocused = false
                    }
                    .accessibilityLabel("Address and search")
            }
            .padding(.horizontal, 11)
            .frame(height: 29)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 13)
        .frame(height: 44)
        .background(.bar)
    }
}
