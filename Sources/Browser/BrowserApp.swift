import AppKit
import SwiftUI

@main
struct BrowserApp: App {
    static let windowID = "browser"
    static let privateWindowID = "private"

    @NSApplicationDelegateAdaptor(BrowserAppDelegate.self) private var appDelegate
    static let profilesWindowID = "profiles"
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
        } defaultValue: {
            ProfileWindowRequest(profileID: profiles.selectedID)
        }
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)
        .commands {
            BrowserCommands(profiles: profiles, updater: .shared)
        }

        WindowGroup("Private Window", id: Self.privateWindowID, for: ProfileWindowRequest.self) { $request in
            ProfileBrowserWindow(profiles: profiles, profileID: request.profileID, isPrivate: true)
                .frame(minWidth: 680, minHeight: 440)
        } defaultValue: {
            ProfileWindowRequest(profileID: profiles.selectedID)
        }
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)

        Window("Profiles", id: Self.profilesWindowID) {
            ProfilesView(profiles: profiles)
        }
        .windowResizability(.contentSize)
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
    private var context: ProfileContext? { profiles.context(for: profileID) }

    private var bookmarkableTab: BrowserTab? {
        guard let tab = browser?.activeTab, !tab.isNewTab, tab.url != nil else { return nil }
        return tab
    }

    private var pageTab: BrowserTab? {
        guard let tab = browser?.activeTab, !tab.isNewTab else { return nil }
        return tab
    }

    var body: some Commands {
        if updater.isAvailable {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        }
        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: BrowserApp.windowID, value: ProfileWindowRequest(profileID: profileID)) }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Private Window") { openWindow(id: BrowserApp.privateWindowID, value: ProfileWindowRequest(profileID: profileID)) }
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
            Picker("Bookmarks Bar", selection: Binding(get: { bookmarksBarVisibility }, set: { bookmarksBarVisibility = $0 })) {
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
        CommandMenu("Profiles") {
            ForEach(profiles.availableProfiles) { profile in
                Button {
                    profiles.activate(profile.id, openWindow: openWindow)
                } label: {
                    if profile.id == profileID { Label(profile.name, systemImage: "checkmark") }
                    else { Label(profile.name, systemImage: profile.icon.rawValue) }
                }
            }
            Divider()
            Button("Next Profile") { profiles.switchProfile(from: profileID, direction: 1, openWindow: openWindow) }
                .keyboardShortcut("]", modifiers: [.command, .option])
                .disabled(profiles.availableProfiles.count < 2)
            Button("Previous Profile") { profiles.switchProfile(from: profileID, direction: -1, openWindow: openWindow) }
                .keyboardShortcut("[", modifiers: [.command, .option])
                .disabled(profiles.availableProfiles.count < 2)
            Divider()
            Button("Manage Profiles…") { openWindow(id: BrowserApp.profilesWindowID) }
        }
        CommandMenu("History") {
            Button("Back") { browser?.goBack() }
                .keyboardShortcut("[", modifiers: .command)
            Button("Forward") { browser?.goForward() }
                .keyboardShortcut("]", modifiers: .command)
            Divider()
            Button("Reopen All Windows from Last Session") {
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
                    Button(Self.menuTitle(visit.displayTitle)) { browser?.open(visit.url) }
                }
            }

            Divider()
            Button("Show All History") { browser?.isShowingHistory.toggle() }
                .keyboardShortcut("y", modifiers: .command)
                .disabled(browser?.history == nil)
            Button("Clear History and Website Data…") { browser?.isShowingClearData = true }
                .disabled(browser == nil || browser?.isPrivate == true)
        }
        CommandMenu("Bookmarks") {
            Button(bookmarks?.isBookmarked(bookmarkableTab?.url) == true ? "Remove Bookmark" : "Bookmark This Page") {
                guard let tab = bookmarkableTab, let url = tab.url else { return }
                bookmarks?.toggle(title: tab.pageTitle, url: url)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(bookmarkableTab == nil)

            if let bookmarks, !bookmarks.bookmarks.isEmpty {
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
