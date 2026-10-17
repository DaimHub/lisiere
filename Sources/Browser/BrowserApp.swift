import AppKit
import SwiftUI

@main
struct BrowserApp: App {
    static let windowID = "browser"
    static let privateWindowID = "private"

    @NSApplicationDelegateAdaptor(BrowserAppDelegate.self) private var appDelegate
    @State private var profiles: ProfileStore

    init() {
        // Tests must not read, restore, or overwrite the user's profile registry or sessions.
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        _profiles = State(initialValue: testing
            ? ProfileStore(root: nil, defaults: UserDefaults(suiteName: "Lisiere.Tests.\(UUID())")!,
                           dataStoreFactory: { _ in .nonPersistent() })
            : ProfileStore())
    }

    var body: some Scene {
        WindowGroup(id: Self.windowID, for: ProfileWindowRequest.self) { $request in
            ProfileBrowserWindow(profiles: profiles, profileID: request.profileID)
                .frame(minWidth: 680, minHeight: 440)
                // SwiftUI selects a scene before forwarding URLs to the app delegate. Without this,
                // it creates a new window for every URL, even though our router can reuse an existing one.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        } defaultValue: {
            ProfileWindowRequest(profileID: profiles.defaultWindowProfileID)
        }
        .handlesExternalEvents(matching: ["*"])
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)
        .commands {
            BrowserCommands(profiles: profiles, updater: .shared)
            #if DEBUG
            BrowserDevelopmentCommands()
            #endif
        }

        WindowGroup("Private Window", id: Self.privateWindowID) {
            ProfileBrowserWindow(profiles: profiles, profileID: BrowserProfile.initialID, isPrivate: true)
                .frame(minWidth: 680, minHeight: 440)
        }
        // External links must create a normal window when only private windows remain.
        .handlesExternalEvents(matching: [])
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)

        Settings { ProfileSettings(profiles: profiles) }
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
    let profiles: ProfileStore
    let updater: AppUpdater
    @FocusedValue(\.browserModel) private var browser
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    private var bookmarks: BookmarkStore? { context?.bookmarks }
    private var bookmarksBarVisibility: BookmarksBarVisibility {
        get { context?.preferences.bookmarksBarVisibility ?? .always }
        nonmutating set { context?.preferences.bookmarksBarVisibility = newValue }
    }
    private var tabLayout: TabLayout {
        get { context?.preferences.tabLayout ?? .horizontal }
        nonmutating set { context?.preferences.tabLayout = newValue }
    }

    private var profileID: UUID { browser?.profileID ?? profiles.selectedID }
    private var context: ProfileContext? { browser?.isPrivate == true ? nil : profiles.context(for: profileID) }

    private var bookmarkableTab: BrowserTab? {
        guard browser?.isPrivate == false, let tab = browser?.activeTab, !tab.isNewTab, tab.url != nil else { return nil }
        return tab
    }

    private var pageTab: BrowserTab? {
        guard let tab = browser?.activeTab, !tab.isNewTab else { return nil }
        return tab
    }

    var body: some Commands {
        if updater.isAvailable {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…", browserIcon: .reload) { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        }
        CommandGroup(replacing: .newItem) {
            Button("New Window", browserIcon: .window) { openWindow(id: BrowserApp.windowID, value: ProfileWindowRequest(profileID: profileID)) }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Private Window", browserIcon: .privateWindow) { openWindow(id: BrowserApp.privateWindowID) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Tab", browserIcon: .add) { browser?.addTab() }
                .keyboardShortcut("t", modifiers: .command)
            Button("Reopen Closed Tab", browserIcon: .reopen) { browser?.reopenClosedTab() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("Close Tab", browserIcon: .close) { browser?.closeActiveTab() }
                .keyboardShortcut("w", modifiers: .command)
        }
        CommandGroup(replacing: .printItem) {
            Button("Print…", browserIcon: .printPage) { browser?.printActivePage() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(pageTab?.webView == nil)
        }
        CommandGroup(replacing: .textEditing) {
            Menu("Find", browserIcon: .search) {
                Button("Find…", browserIcon: .search) { browser?.showFindBar() }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Find Next", browserIcon: .chevronDown) { browser?.findNext() }
                    .keyboardShortcut("g", modifiers: .command)
                Button("Find Previous", browserIcon: .chevronUp) { browser?.findNext(backwards: true) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Use Selection for Find", browserIcon: .selection) { browser?.useSelectionForFind() }
                    .keyboardShortcut("e", modifiers: .command)
            }
            .disabled(pageTab == nil)
            // Replacing the group removes these too, so they're sent to the page or text field as AppKit would.
            Menu("Spelling and Grammar", browserIcon: .spelling) {
                Button("Show Spelling and Grammar", browserIcon: .spelling) { send(#selector(NSText.showGuessPanel(_:))) }
                    .keyboardShortcut(":", modifiers: .command)
                Button("Check Document Now", browserIcon: .spelling) { send(#selector(NSText.checkSpelling(_:))) }
                    .keyboardShortcut(";", modifiers: .command)
            }
            Menu("Speech", browserIcon: .speak) {
                Button("Start Speaking", browserIcon: .speak) { send(#selector(NSTextView.startSpeaking(_:))) }
                Button("Stop Speaking", browserIcon: .stop) { send(#selector(NSTextView.stopSpeaking(_:))) }
            }
        }
        CommandMenu("Tabs") {
            Button("Next Tab", browserIcon: .forward) { browser?.switchTab(by: 1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Tab", browserIcon: .back) { browser?.switchTab(by: -1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Button("Cycle to Next Tab", browserIcon: .forward) { browser?.switchTab(by: 1) }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("Cycle to Previous Tab", browserIcon: .back) { browser?.switchTab(by: -1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])

            Divider()

            ForEach(1...8, id: \.self) { number in
                Button("Select Tab \(number)", browserIcon: .window) { browser?.selectTab(at: number - 1) }
                    .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
            }
            Button("Select Last Tab", browserIcon: .forward) { browser?.selectLastTab() }
                .keyboardShortcut("9", modifiers: .command)
        }
        CommandGroup(after: .toolbar) {
            Button("Open Location", browserIcon: .search) { browser?.requestAddressFocus() }
                .keyboardShortcut("l", modifiers: .command)
            Button("Reload Page", browserIcon: .reload) { browser?.reload() }
                .keyboardShortcut("r", modifiers: .command)
            Divider()
            Button("Actual Size", browserIcon: .actualSize) { browser?.resetZoom() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(pageTab.map { $0.pageZoom == 1 } ?? true)
            Button("Zoom In", browserIcon: .zoomIn) { browser?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!(browser?.canZoom ?? false))
            Button("Zoom Out", browserIcon: .zoomOut) { browser?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!(browser?.canZoom ?? false))
        }
        CommandGroup(after: .sidebar) {
            Button(browser?.isSplitView == true ? "Exit Split View" : "Split View with New Tab", browserIcon: .splitView) {
                guard let browser else { return }
                if browser.isSplitView { browser.endSplitView() } else { browser.startSplitView() }
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(browser == nil)
            Button("Focus Other Pane", browserIcon: .splitView) { browser?.focusOtherSplitPane() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .control])
                .disabled(browser?.isSplitView != true)
            Divider()
            Button(tabLayout == .vertical ? "Use Horizontal Tabs" : "Use Vertical Tabs",
                   browserIcon: tabLayout == .vertical ? .horizontalTabs : .verticalTabs) {
                tabLayout = tabLayout.toggled
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Picker("Bookmarks Bar", selection: Binding(get: { bookmarksBarVisibility }, set: { bookmarksBarVisibility = $0 })) {
                ForEach(BookmarksBarVisibility.allCases) { visibility in
                    Text(visibility.title).tag(visibility)
                }
            }
            Button(bookmarksBarVisibility == .never ? "Show Bookmarks Bar" : "Hide Bookmarks Bar",
                   browserIcon: .book) {
                bookmarksBarVisibility = bookmarksBarVisibility == .never ? .always : .never
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            Divider()
        }
        CommandMenu("Profiles") {
            ForEach(profiles.availableProfiles) { profile in
                Button {
                    profiles.activate(profile.id, in: browser, openWindow: openWindow)
                } label: {
                    BrowserMenuLabel(title: profile.name,
                                     icon: profile.id == profileID ? .checkmark : profile.icon.browserIcon)
                }
            }
            Divider()
            Button("Next Profile", browserIcon: .forward) { profiles.switchProfile(from: profileID, direction: 1, in: browser, openWindow: openWindow) }
                .keyboardShortcut("]", modifiers: [.command, .option])
                .disabled(profiles.availableProfiles.count < 2)
            Button("Previous Profile", browserIcon: .back) { profiles.switchProfile(from: profileID, direction: -1, in: browser, openWindow: openWindow) }
                .keyboardShortcut("[", modifiers: [.command, .option])
                .disabled(profiles.availableProfiles.count < 2)
            Divider()
            Button("Manage Profiles…", browserIcon: .profiles) {
                profiles.settingsTab = .profiles
                openSettings()
            }
        }
        CommandMenu("History") {
            Button("Back", browserIcon: .back) { browser?.goBack() }
                .keyboardShortcut("[", modifiers: .command)
            Button("Forward", browserIcon: .forward) { browser?.goForward() }
                .keyboardShortcut("]", modifiers: .command)
            Divider()
            Button("Reopen All Windows from Last Session", browserIcon: .reopen) {
                guard let session = context?.session else { return }
                // A private window can't take the restored tabs.
                for _ in 0..<session.reopenLastSession(reusing: browser?.isPrivate == true ? nil : browser) {
                    openWindow(id: BrowserApp.windowID, value: ProfileWindowRequest(profileID: profileID))
                }
            }
            .disabled(context?.session.reopenableWindows.isEmpty ?? true)

            let recentVisits = browser?.isPrivate == true ? [] : (context?.history.recentVisits(limit: 15) ?? [])
            if !recentVisits.isEmpty {
                Divider()
                ForEach(recentVisits) { visit in
                    Button(Self.menuTitle(visit.displayTitle), browserIcon: .history) { browser?.open(visit.url) }
                }
            }

            Divider()
            Button("Show All History", browserIcon: .history) { browser?.isShowingHistory.toggle() }
                .keyboardShortcut("y", modifiers: .command)
                .disabled(browser?.history == nil)
            Button("Clear History and Website Data…", browserIcon: .trash) { browser?.isShowingClearData = true }
                .disabled(browser == nil || browser?.isPrivate == true)
        }
        CommandMenu("Bookmarks") {
            Button(bookmarks?.isBookmarked(bookmarkableTab?.url) == true ? "Remove Bookmark" : "Bookmark This Page",
                   browserIcon: bookmarks?.isBookmarked(bookmarkableTab?.url) == true ? .bookmarkSelected : .bookmark) {
                guard let tab = bookmarkableTab, let url = tab.url else { return }
                bookmarks?.toggle(title: tab.pageTitle, url: url)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(bookmarkableTab == nil)

            if let bookmarks, !bookmarks.bookmarks.isEmpty {
                Divider()
                ForEach(bookmarks.bookmarks) { bookmark in
                    Button(bookmark.displayTitle, browserIcon: .bookmark) { browser?.open(bookmark.url) }
                }
            }
        }
    }

    /// Sends an editing action to the focused page or text field.
    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }

    private static func menuTitle(_ title: String) -> String {
        title.count > 60 ? String(title.prefix(59)) + "…" : title
    }
}

#if DEBUG
/// Keep the development menu separate: older SDKs limit CommandsBuilder to ten children.
private struct BrowserDevelopmentCommands: Commands {
    @FocusedValue(\.browserModel) private var browser

    var body: some Commands {
        CommandMenu("Develop") {
            Button("Show Web Inspector", browserIcon: .code) { browser?.showWebInspector() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(browser?.activeTab?.isNewTab != false)
        }
    }
}
#endif
