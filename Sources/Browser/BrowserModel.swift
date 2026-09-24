import AppKit
import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class BrowserModel {
    static let studioVisibilityKey = "studioVisible"

    private(set) var tabs: [BrowserTab] = []
    private var closedTabs: [ClosedTab] = []
    var activeTabID: UUID? {
        didSet {
            // Keep a preview of the page being left for background-tab hover cards.
            guard oldValue != activeTabID, let previousTab = tab(withID: oldValue) else { return }
            previousTab.captureThumbnail(afterScreenUpdates: false)
        }
    }
    var addressFocusRequest = 0

    private struct ClosedTab {
        let url: URL?
        /// The tab's back-forward history, restored when it reopens.
        let interactionState: Any?
    }

    init() {
        addTab()
    }

    var activeTab: BrowserTab? {
        tab(withID: activeTabID)
    }

    var canReopenClosedTab: Bool {
        !closedTabs.isEmpty
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
        let original = tabs[index]
        let tab = BrowserTab()
        if original.url != nil {
            tab.isNewTab = false
            tab.webView.interactionState = original.webView.interactionState
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
        let isBlank = tab.isNewTab || tab.url == nil
        closedTabs.append(ClosedTab(url: isBlank ? nil : tab.url,
                                    interactionState: isBlank ? nil : tab.webView.interactionState))
        if closedTabs.count > 10 { closedTabs.removeFirst() }
    }

    func reopenClosedTab() {
        guard let closedTab = closedTabs.popLast() else { return }
        addTab()
        guard let tab = activeTab else { return }
        if let interactionState = closedTab.interactionState {
            tab.isNewTab = false
            tab.webView.interactionState = interactionState
        } else if let url = closedTab.url {
            tab.load(url)
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
        activeTab?.load(url)
    }

    func navigate(to input: String) {
        guard let url = BrowserAddress.url(for: input) else { return }
        activeTab?.load(url)
    }

    func reload() {
        guard let activeTabID else { return }
        reloadTab(activeTabID)
    }

    func reloadTab(_ id: UUID) {
        guard let tab = tab(withID: id), !tab.isNewTab else { return }
        tab.webView.reload()
    }

    func stopLoading() {
        activeTab?.webView.stopLoading()
    }

    func goBack() {
        activeTab?.webView.goBack()
    }

    func goForward() {
        activeTab?.webView.goForward()
    }

    func go(to item: WKBackForwardListItem) {
        activeTab?.webView.go(to: item)
    }

    func requestAddressFocus() {
        addressFocusRequest += 1
    }

    func showWebInspector() {
        guard let tab = activeTab, !tab.isNewTab else { return }
        WebInspector.show(for: tab.webView)
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
