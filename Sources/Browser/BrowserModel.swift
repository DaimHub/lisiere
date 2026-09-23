import AppKit
import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class BrowserTab: Identifiable {
    let id = UUID()
    let page: WebPage

    init() {
        var configuration = WebPage.Configuration()
        let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")
        let safariVersion = safariURL.flatMap { Bundle(url: $0)?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
            ?? "\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).0"
        configuration.applicationNameForUserAgent = "Version/\(safariVersion) Safari/605.1.15"
        page = WebPage(configuration: configuration)
    }

    var title: String {
        if !page.title.isEmpty { return page.title }
        return page.url?.host() ?? "New Tab"
    }
}

@MainActor
@Observable
final class BrowserModel {
    private(set) var tabs: [BrowserTab] = []
    var activeTabID: UUID?
    var addressFocusRequest = 0

    init() {
        addTab()
    }

    var activeTab: BrowserTab? {
        tabs.first { $0.id == activeTabID }
    }

    func addTab() {
        let tab = BrowserTab()
        tabs.append(tab)
        activeTabID = tab.id
        _ = tab.page.load(URL(string: "https://www.apple.com"))
    }

    func closeActiveTab() {
        guard let activeTabID else { return }
        closeTab(activeTabID)
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if tabs.isEmpty {
            addTab()
        } else if activeTabID == id {
            activeTabID = tabs[min(index, tabs.count - 1)].id
        }
    }

    func navigate(to input: String) {
        guard let url = BrowserAddress.url(for: input), let page = activeTab?.page else { return }
        _ = page.load(url)
    }

    func reload() {
        guard let page = activeTab?.page else { return }
        _ = page.reload(fromOrigin: false)
    }

    func goBack() {
        guard let page = activeTab?.page, let item = page.backForwardList.backList.last else { return }
        _ = page.load(item)
    }

    func goForward() {
        guard let page = activeTab?.page, let item = page.backForwardList.forwardList.first else { return }
        _ = page.load(item)
    }

    func requestAddressFocus() {
        addressFocusRequest += 1
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
