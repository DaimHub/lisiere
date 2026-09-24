import AppKit
import Foundation
import Observation
import SwiftUI
import WebKit

@MainActor
@Observable
final class BrowserTab: Identifiable {
    let id = UUID()
    let page: WebPage
    var isNewTab = true
    var favicon: Image?
    var thumbnail: Image?
    @ObservationIgnored var viewportSize: CGSize = .zero
    private var faviconHost: String?

    init() {
        var configuration = WebPage.Configuration()
        let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")
        let safariVersion = safariURL.flatMap { Bundle(url: $0)?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
            ?? "\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).0"
        configuration.applicationNameForUserAgent = "Version/\(safariVersion) Safari/605.1.15"
        page = WebPage(configuration: configuration)
        page.isInspectable = true
    }

    var title: String {
        if !page.title.isEmpty { return page.title }
        return page.url?.host() ?? "New Tab"
    }

    var host: String? {
        page.url?.host()
    }

    var isSecure: Bool {
        page.url?.scheme == "https" && page.hasOnlySecureContent
    }

    func captureThumbnail(afterScreenUpdates: Bool = true) async {
        guard !isNewTab, viewportSize.width > 0, viewportSize.height > 0 else { return }
        let region = WebPage.ExportedContentConfiguration.Region.rect(CGRect(origin: .zero, size: viewportSize))
        guard let data = try? await page.exported(as: .image(region: region,
                                                             snapshotWidth: 520,
                                                             afterScreenUpdates: afterScreenUpdates)),
              let image = NSImage(data: data) else { return }
        thumbnail = Image(nsImage: image)
    }

    func updateFavicon() async {
        guard let url = page.url, let host = url.host() else {
            favicon = nil
            faviconHost = nil
            return
        }
        guard faviconHost != host else { return }

        favicon = FaviconStore.cachedIcon(for: url)
        if favicon != nil {
            faviconHost = host
            return
        }

        guard let icon = await FaviconStore.icon(for: url),
              !Task.isCancelled,
              page.url?.host() == host else { return }
        faviconHost = host
        favicon = icon
    }
}

@MainActor
@Observable
final class BrowserModel {
    private(set) var tabs: [BrowserTab] = []
    private var closedTabURLs: [URL?] = []
    var activeTabID: UUID? {
        didSet {
            // Keep a preview of the page being left for background-tab hover cards.
            guard oldValue != activeTabID, let previousTab = tab(withID: oldValue) else { return }
            Task { await previousTab.captureThumbnail(afterScreenUpdates: false) }
        }
    }
    var addressFocusRequest = 0

    init() {
        addTab()
    }

    var activeTab: BrowserTab? {
        tab(withID: activeTabID)
    }

    var canReopenClosedTab: Bool {
        !closedTabURLs.isEmpty
    }

    func tab(withID id: UUID?) -> BrowserTab? {
        guard let id else { return nil }
        return tabs.first { $0.id == id }
    }

    func addTab() {
        let tab = BrowserTab()
        tabs.append(tab)
        activeTabID = tab.id
        requestAddressFocus()
    }

    func duplicateTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = BrowserTab()
        if let url = tabs[index].page.url {
            tab.isNewTab = false
            _ = tab.page.load(url)
        }
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

    private func rememberClosedTab(_ tab: BrowserTab) {
        closedTabURLs.append(tab.page.url)
        if closedTabURLs.count > 10 { closedTabURLs.removeFirst() }
    }

    func reopenClosedTab() {
        guard let url = closedTabURLs.popLast() else { return }
        addTab()
        if let url, let tab = activeTab {
            tab.isNewTab = false
            _ = tab.page.load(url)
        }
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
            let tab = BrowserTab()
            tabs.append(tab)
            activeTabID = tab.id
        }
        guard let tab = activeTab else { return }
        tab.isNewTab = false
        _ = tab.page.load(url)
    }

    func navigate(to input: String) {
        guard let url = BrowserAddress.url(for: input), let tab = activeTab else { return }
        tab.isNewTab = false
        _ = tab.page.load(url)
    }

    func reload() {
        guard let activeTabID else { return }
        reloadTab(activeTabID)
    }

    func reloadTab(_ id: UUID) {
        guard let tab = tab(withID: id), !tab.isNewTab else { return }
        _ = tab.page.reload(fromOrigin: false)
    }

    func goBack() {
        guard let page = activeTab?.page, let item = page.backForwardList.backList.last else { return }
        _ = page.load(item)
    }

    func goForward() {
        guard let page = activeTab?.page, let item = page.backForwardList.forwardList.first else { return }
        _ = page.load(item)
    }

    func go(to item: WebPage.BackForwardList.Item) {
        _ = activeTab?.page.load(item)
    }

    func requestAddressFocus() {
        addressFocusRequest += 1
    }

    func showWebInspector() {
        guard activeTab?.isNewTab == false,
              let contentView = NSApp.keyWindow?.contentView,
              let webView = WebInspector.findWebView(in: contentView) else { return }
        WebInspector.show(for: webView)
    }
}

enum BrowserAddress {
    static func url(for input: String) -> URL? {
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

        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: text)]
        return components?.url
    }
}
