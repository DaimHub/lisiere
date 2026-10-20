import SwiftUI

/// Keep the start-page graph and the native page host stable when switching between them.
/// Only the selected web page is visible; hidden start-page motion is paused.
struct BrowserPage: View {
    let bookmarks: BookmarkStore
    let browser: BrowserModel
    let tab: BrowserTab
    let accent: Color
    let focusAddress: () -> Void
    let updateAddress: (URL?) -> Void
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            BrowserWebPage(tab: tab, browser: browser, accent: accent, updateAddress: updateAddress)
                .transaction { $0.animation = nil }
                .opacity(tab.isNewTab ? 0 : 1)
                .allowsHitTesting(!tab.isNewTab && browser.isActiveInWorkspace)
                .accessibilityHidden(tab.isNewTab || !browser.isActiveInWorkspace)
            RetainedStartPage(bookmarks: bookmarks, browser: browser,
                              tab: tab.isNewTab && browser.isActiveInWorkspace ? tab : nil,
                              showsHomePage: tab.showsHomePage,
                              isVisible: tab.isNewTab && browser.isActiveInWorkspace, focusAddress: focusAddress)
                .equatable()
                .transaction { $0.animation = nil }
                .environment(\.scenePhase, tab.isNewTab && browser.isActiveInWorkspace ? scenePhase : .inactive)
                .opacity(tab.isNewTab ? 1 : 0)
                .allowsHitTesting(tab.isNewTab && browser.isActiveInWorkspace)
                .accessibilityHidden(!tab.isNewTab || !browser.isActiveInWorkspace)
        }
    }
}

/// The hidden start page does not depend on which web tab is selected. Preserve its inputs
/// until it becomes visible again; model observations still update preferences and bookmarks.
private struct RetainedStartPage: View, Equatable {
    let bookmarks: BookmarkStore
    let browser: BrowserModel
    let tab: BrowserTab?
    let showsHomePage: Bool
    let isVisible: Bool
    let focusAddress: () -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.bookmarks === rhs.bookmarks && lhs.browser === rhs.browser
            && lhs.isVisible == rhs.isVisible
            && (!rhs.isVisible || (lhs.tab === rhs.tab && lhs.showsHomePage == rhs.showsHomePage))
    }

    var body: some View {
        NewTabView(bookmarks: bookmarks, browser: browser, tab: tab,
                   isVisible: isVisible, showsHomePage: showsHomePage, focusAddress: focusAddress)
    }
}
