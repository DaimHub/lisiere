import AppKit
import SwiftUI

@main
struct BrowserApp: App {
    static let windowID = "browser"
    static let privateWindowID = "private"

    @State private var bookmarks = BookmarkStore()
    @State private var downloads = DownloadManager()
    @State private var history: HistoryStore
    @State private var session: SessionStore
    @State private var browsingData: BrowsingData

    init() {
        let history = HistoryStore(file: Self.storeFile(named: "History.plist"))
        let session = SessionStore(file: Self.storeFile(named: "Session.plist"),
                                   restoresWindows: SessionPreferences.restoresWindows)
        _history = State(initialValue: history)
        _session = State(initialValue: session)
        _browsingData = State(initialValue: BrowsingData(history: history, session: session))
    }

    /// Unit tests run inside the app, which then shouldn't reopen or overwrite the user's windows and history.
    private static func storeFile(named name: String) -> StoreFile? {
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        return isRunningTests ? nil : .applicationSupport(named: name)
    }

    var body: some Scene {
        WindowGroup(id: Self.windowID) {
            BrowserWindow(bookmarks: bookmarks, downloads: downloads, history: history, session: session)
                .frame(minWidth: 680, minHeight: 440)
                .environment(browsingData)
        }
        .windowStyle(.hiddenTitleBar)
        // The session store reopens the windows with their tabs, so the system doesn't reopen them too.
        .restorationBehavior(.disabled)
        .commands {
            BrowserCommands(bookmarks: bookmarks, history: history, session: session)
        }

        // A private window joins neither history nor the session, and isn't reopened.
        WindowGroup("Private Window", id: Self.privateWindowID) {
            BrowserWindow(bookmarks: bookmarks, downloads: downloads, history: nil, session: nil, isPrivate: true)
                .frame(minWidth: 680, minHeight: 440)
                .environment(browsingData)
        }
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView(browsingData: browsingData, contentBlocker: .shared, sitePermissions: .shared,
                         zoomLevels: .shared)
        }
    }
}

private struct BrowserModelKey: FocusedValueKey {
    typealias Value = BrowserModel
}

extension FocusedValues {
    var browserModel: BrowserModel? {
        get { self[BrowserModelKey.self] }
        set { self[BrowserModelKey.self] = newValue }
    }
}

private struct BrowserCommands: Commands {
    let bookmarks: BookmarkStore
    let history: HistoryStore
    let session: SessionStore
    @FocusedValue(\.browserModel) private var browser
    @Environment(\.openWindow) private var openWindow
    @AppStorage(BookmarksBarVisibility.storageKey) private var bookmarksBarVisibility = BookmarksBarVisibility.always
    @AppStorage(TabLayout.storageKey) private var tabLayout = TabLayout.horizontal

    private var bookmarkableTab: BrowserTab? {
        guard let tab = browser?.activeTab, !tab.isNewTab, tab.url != nil else { return nil }
        return tab
    }

    private var pageTab: BrowserTab? {
        guard let tab = browser?.activeTab, !tab.isNewTab else { return nil }
        return tab
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: BrowserApp.windowID) }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Private Window") { openWindow(id: BrowserApp.privateWindowID) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Tab") { browser?.addTab() }
                .keyboardShortcut("t", modifiers: .command)
            Button("Reopen Closed Tab") { browser?.reopenClosedTab() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("Close Tab") { browser?.closeActiveTab() }
                .keyboardShortcut("w", modifiers: .command)
        }
        CommandGroup(replacing: .printItem) {
            Button("Print…") { browser?.printActivePage() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(pageTab?.webView == nil)
        }
        CommandGroup(replacing: .textEditing) {
            Menu("Find") {
                Button("Find…") { browser?.showFindBar() }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Find Next") { browser?.findNext() }
                    .keyboardShortcut("g", modifiers: .command)
                Button("Find Previous") { browser?.findNext(backwards: true) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Use Selection for Find") { browser?.useSelectionForFind() }
                    .keyboardShortcut("e", modifiers: .command)
            }
            .disabled(pageTab == nil)
            // Replacing the group removes these too, so they're sent to the page or text field as AppKit would.
            Menu("Spelling and Grammar") {
                Button("Show Spelling and Grammar") { send(#selector(NSText.showGuessPanel(_:))) }
                    .keyboardShortcut(":", modifiers: .command)
                Button("Check Document Now") { send(#selector(NSText.checkSpelling(_:))) }
                    .keyboardShortcut(";", modifiers: .command)
            }
            Menu("Speech") {
                Button("Start Speaking") { send(#selector(NSTextView.startSpeaking(_:))) }
                Button("Stop Speaking") { send(#selector(NSTextView.stopSpeaking(_:))) }
            }
        }
        CommandMenu("Tabs") {
            Button("Next Tab") { browser?.switchTab(by: 1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Tab") { browser?.switchTab(by: -1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Button("Cycle to Next Tab") { browser?.switchTab(by: 1) }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("Cycle to Previous Tab") { browser?.switchTab(by: -1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])

            Divider()

            ForEach(1...8, id: \.self) { number in
                Button("Select Tab \(number)") { browser?.selectTab(at: number - 1) }
                    .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
            }
            Button("Select Last Tab") { browser?.selectLastTab() }
                .keyboardShortcut("9", modifiers: .command)
        }
        CommandGroup(after: .toolbar) {
            Button("Open Location") { browser?.requestAddressFocus() }
                .keyboardShortcut("l", modifiers: .command)
            Button("Reload Page") { browser?.reload() }
                .keyboardShortcut("r", modifiers: .command)
            Divider()
            Button("Actual Size") { browser?.resetZoom() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(pageTab.map { $0.pageZoom == 1 } ?? true)
            Button("Zoom In") { browser?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!(browser?.canZoom ?? false))
            Button("Zoom Out") { browser?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!(browser?.canZoom ?? false))
        }
        CommandGroup(after: .sidebar) {
            Button(tabLayout == .vertical ? "Use Horizontal Tabs" : "Use Vertical Tabs") {
                tabLayout = tabLayout.toggled
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Picker("Bookmarks Bar", selection: $bookmarksBarVisibility) {
                ForEach(BookmarksBarVisibility.allCases) { visibility in
                    Text(visibility.title).tag(visibility)
                }
            }
            Button(bookmarksBarVisibility == .never ? "Show Bookmarks Bar" : "Hide Bookmarks Bar") {
                bookmarksBarVisibility = bookmarksBarVisibility == .never ? .always : .never
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            Divider()
        }
        CommandMenu("History") {
            Button("Back") { browser?.goBack() }
                .keyboardShortcut("[", modifiers: .command)
            Button("Forward") { browser?.goForward() }
                .keyboardShortcut("]", modifiers: .command)
            Divider()
            Button("Reopen All Windows from Last Session") {
                // A private window can't take the restored tabs.
                for _ in 0..<session.reopenLastSession(reusing: browser?.isPrivate == true ? nil : browser) {
                    openWindow(id: BrowserApp.windowID)
                }
            }
            .disabled(session.reopenableWindows.isEmpty)

            let recentVisits = history.recentVisits(limit: 15)
            if !recentVisits.isEmpty {
                Divider()
                ForEach(recentVisits) { visit in
                    Button(Self.menuTitle(visit.displayTitle)) { browser?.open(visit.url) }
                }
            }

            Divider()
            Button("Show All History") { browser?.isShowingHistory.toggle() }
                .keyboardShortcut("y", modifiers: .command)
                .disabled(browser?.history == nil)
            Button("Clear History and Website Data…") { browser?.isShowingClearData = true }
                .disabled(browser == nil)
        }
        CommandMenu("Bookmarks") {
            Button(bookmarks.isBookmarked(bookmarkableTab?.url) ? "Remove Bookmark" : "Bookmark This Page") {
                guard let tab = bookmarkableTab, let url = tab.url else { return }
                bookmarks.toggle(title: tab.pageTitle, url: url)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(bookmarkableTab == nil)

            if !bookmarks.bookmarks.isEmpty {
                Divider()
                ForEach(bookmarks.bookmarks) { bookmark in
                    Button(bookmark.displayTitle) { browser?.open(bookmark.url) }
                }
            }
        }
        #if DEBUG
        CommandMenu("Develop") {
            Button("Show Web Inspector") { browser?.showWebInspector() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(browser?.activeTab?.isNewTab != false)
        }
        #endif
    }

    /// Sends an editing action to the focused page or text field.
    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }

    private static func menuTitle(_ title: String) -> String {
        title.count > 60 ? String(title.prefix(59)) + "…" : title
    }
}
