import SwiftUI

/// Keep the start-page graph and the native page host stable when switching between them.
/// Only the selected web page is attached; hidden start-page motion is paused.
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
            NewTabView(bookmarks: bookmarks, browser: browser, tab: tab, focusAddress: focusAddress)
                .transaction { $0.animation = nil }
                .environment(\.scenePhase, tab.isNewTab ? scenePhase : .inactive)
                .opacity(tab.isNewTab ? 1 : 0)
                .allowsHitTesting(tab.isNewTab && browser.isActiveInWorkspace)
                .accessibilityHidden(!tab.isNewTab || !browser.isActiveInWorkspace)
        }
    }
}
