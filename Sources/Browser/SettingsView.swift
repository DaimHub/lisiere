import LocalAuthentication
import SwiftUI
import WebKit

enum SettingsTab: Hashable {
    case general, appearance, privacy, passwords, sites, downloads, profiles
}

/// Lisière ▸ Settings (⌘,). Manage Profiles routes to this same window's Profiles tab.
struct SettingsView: View {
    @Bindable var profiles: ProfileStore
    let passkeys: Passkeys
    let updater: AppUpdater

    var body: some View {
        VStack(spacing: 0) {
            if profiles.settingsTab != .profiles {
                Picker("Profile", selection: Binding(get: { profiles.selectedID }, set: { id in
                    do { try profiles.select(id) } catch { profiles.errorMessage = error.localizedDescription }
                })) {
                    ForEach(profiles.availableProfiles) { profile in
                        Label(profile.name, systemImage: profile.icon.rawValue).tag(profile.id)
                    }
                }
                .padding()
                Divider()
            }
            // Keep tab metadata outside profile-dependent view identity. macOS otherwise
            // creates empty toolbar items for tabs whose content has an explicit .id.
            TabView(selection: $profiles.settingsTab) {
                Tab("General", systemImage: "gearshape", value: SettingsTab.general) { profileContent(.general) }
                Tab("Appearance", systemImage: "macwindow", value: SettingsTab.appearance) { profileContent(.appearance) }
                Tab("Privacy", systemImage: "hand.raised", value: SettingsTab.privacy) { profileContent(.privacy) }
                Tab("Passwords", systemImage: "key", value: SettingsTab.passwords) { profileContent(.passwords) }
                Tab("Site Settings", systemImage: "globe", value: SettingsTab.sites) { profileContent(.sites) }
                Tab("Downloads", systemImage: "arrow.down.circle", value: SettingsTab.downloads) { profileContent(.downloads) }
                Tab("Profiles", systemImage: "person.2", value: SettingsTab.profiles) { ProfilesView(profiles: profiles) }
            }
        }
        .preferredColorScheme(profiles.context(for: profiles.selectedID)?.preferences.appearance.selection.colorScheme)
        .tint(profiles.context(for: profiles.selectedID)?.preferences.accentColor ?? .accentColor)
        .formStyle(.grouped)
        .frame(width: 580, height: 560)
        .onAppear { if profiles.loadError != nil { profiles.settingsTab = .profiles } }
    }

    @ViewBuilder private func profileContent(_ tab: SettingsTab) -> some View {
        if let context = profiles.context(for: profiles.selectedID) {
            Group {
                switch tab {
                case .general: GeneralSettings(updater: updater)
                case .appearance: AppearanceSettings()
                case .privacy:
                    PrivacySettings(browsingData: context.browsingData, contentBlocker: context.contentBlocker,
                                    profileName: profiles.name(context.id))
                case .passwords: PasswordSettings(passwords: context.passwords, passkeys: passkeys)
                case .sites:
                    SiteSettings(contentBlocker: context.contentBlocker, sitePermissions: context.sitePermissions,
                                 zoomLevels: context.zoomLevels)
                case .downloads: DownloadSettings()
                case .profiles: EmptyView()
                }
            }
            .environment(context.preferences)
            .environment(context.favicons)
            .id(context.id)
        }
    }

}

private struct GeneralSettings: View {
    @Bindable var updater: AppUpdater
    @State private var defaultBrowser = DefaultBrowser()
    @Environment(ProfilePreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section {
                LabeledContent("Default web browser") {
                    if defaultBrowser.isDefault {
                        Label("Lisière is your default browser", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            if defaultBrowser.isRequesting {
                                ProgressView().controlSize(.small)
                                    .accessibilityLabel("Waiting for macOS")
                            }
                            Button("Make Default…") {
                                Task { await defaultBrowser.makeDefault() }
                            }
                            .disabled(defaultBrowser.isRequesting)
                        }
                    }
                }
                if !defaultBrowser.isDefault {
                    Text(defaultBrowserDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open System Settings…") { defaultBrowser.openSystemSettings() }
                        .disabled(defaultBrowser.isRequesting)
                }
            } footer: {
                if !defaultBrowser.isDefault {
                    Text("In System Settings, choose Desktop & Dock › Default web browser › Lisière.")
                }
            }

            Section {
                Picker("Search engine", selection: $preferences.searchEngine) {
                    ForEach(SearchEngine.allCases) { engine in
                        Text(engine.title).tag(engine)
                    }
                }
                Picker("New tabs open with", selection: $preferences.newTabPage) {
                    ForEach(NewTabPage.allCases) { page in
                        Text(page.title).tag(page)
                    }
                }
                Toggle(isOn: $preferences.restoresWindows) {
                    Text("Reopen windows from last session on launch")
                    Text("When off, History ▸ Reopen All Windows from Last Session opens them.")
                }
            }

            if updater.isAvailable {
                Section("Updates") {
                    Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
                    Toggle("Download and install updates automatically", isOn: $updater.downloadsAutomatically)
                        .disabled(!updater.checksAutomatically)
                    LabeledContent("Software update") {
                        Button("Check Now") { updater.checkForUpdates() }
                            .disabled(!updater.canCheckForUpdates)
                    }
                }
            }
        }
        .task { defaultBrowser.refresh() }
        // The default browser can also change in System Settings while Settings is open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            defaultBrowser.refresh()
        }
    }

    private var defaultBrowserDescription: String {
        if defaultBrowser.isRequesting { return "Confirm your choice in macOS if asked." }
        let status: String = switch defaultBrowser.status {
        case .unknown: "macOS couldn’t confirm the current default browser."
        case .notDefault: "Lisière isn’t your default web browser."
        case .partial: "Lisière opens some web links by default, but not all."
        case .defaultBrowser: "Lisière is your default web browser."
        }
        let notice: String? = switch defaultBrowser.notice {
        case .cancelled: "The request was cancelled."
        case .notCompleted: "macOS hasn’t applied the full change. Try System Settings."
        case .failed: "The request couldn’t be completed. Try System Settings."
        case .settingsUnavailable: "Open System Settings from the Apple menu to continue."
        case nil: nil
        }
        return notice.map { "\(status) \($0)" } ?? status
    }
}

/// Saved passwords stay hidden until the user unlocks them with Touch ID or their login password, and lock again
/// when the tab closes or the app goes to the background.
private struct PasswordSettings: View {
    @Bindable var passwords: PasswordManager
    let passkeys: Passkeys
    @State private var isUnlocked = false
    @State private var query = ""
    @State private var revealed: [SavedPassword.ID: String] = [:]
    @State private var removing: SavedPassword?

    private var accounts: [SavedPassword] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return passwords.passwords }
        return passwords.passwords.filter {
            $0.origin.host.localizedCaseInsensitiveContains(query) || $0.username.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $passwords.offersToSave) {
                    Text("Offer to save passwords")
                    Text("Lisière asks after you sign in to a secure site, keeps passwords in your keychain, and "
                         + "fills them in on that site when you choose. Private windows never save or fill them.")
                }
            }

            Section("Saved Passwords") {
                if isUnlocked {
                    savedPasswords
                } else {
                    HStack {
                        Text("Unlock to see your saved passwords.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Unlock…") { Task { await unlock() } }
                    }
                }
            }

            if !passwords.neverSaveSites.isEmpty {
                Section("Never Saved") {
                    ForEach(passwords.neverSaveSites, id: \.self) { site in
                        HStack {
                            Text(site)
                            Spacer()
                            Button { passwords.allowSaving(on: site) } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Offer to Save Passwords Again")
                        }
                    }
                }
            }

            Section("Passkeys") {
                passkeyStatus
            }
        }
        .onDisappear(perform: lock)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in lock() }
        .confirmationDialog("Remove this saved password?", isPresented: Binding(get: { removing != nil },
                                                                                set: { if !$0 { removing = nil } }),
                            presenting: removing) { account in
            Button("Remove", role: .destructive) {
                revealed[account.id] = nil
                passwords.remove(account)
            }
        } message: { account in
            Text("Lisière forgets the password for \(account.username.isEmpty ? "this site" : "“\(account.username)”") "
                 + "on \(account.origin.host). It can’t be undone.")
        }
    }

    @ViewBuilder
    private var savedPasswords: some View {
        TextField("Search", text: $query, prompt: Text("Search Passwords"))
            .labelsHidden()
        if accounts.isEmpty {
            Text(query.isEmpty ? "No passwords are saved." : "No passwords match “\(query)”.")
                .foregroundStyle(.secondary)
        }
        ForEach(accounts) { account in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.origin.port == 443 ? account.origin.host : "\(account.origin.host):\(account.origin.port)")
                    Text(account.username.isEmpty ? "No user name" : account.username)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(revealed[account.id] ?? "••••••••")
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(1)
                Button {
                    revealed[account.id] = revealed[account.id] == nil ? passwords.password(for: account) : nil
                } label: {
                    Image(systemName: revealed[account.id] == nil ? "eye" : "eye.slash")
                }
                .help(revealed[account.id] == nil ? "Show Password" : "Hide Password")
                Button { copy(account) } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy Password")
                Button { removing = account } label: {
                    Image(systemName: "minus.circle")
                }
                .help("Remove Password")
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var passkeyStatus: some View {
        if !passkeys.isEntitled {
            Text("Signing in with passkeys and security keys isn’t available in this version of Lisière yet.")
                .foregroundStyle(.secondary)
        } else {
            switch passkeys.authorizationState {
            case .authorized:
                Text("Websites can ask you to sign in with your passkeys and security keys.")
                    .foregroundStyle(.secondary)
            case .notDetermined:
                LabeledContent("Use your passkeys on websites") {
                    Button("Allow…") { passkeys.requestAuthorizationIfNeeded() }
                }
            default:
                Text("Lisière isn’t allowed to use your passkeys. You can allow it in System Settings.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func unlock() async {
        let context = LAContext()
        guard (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                 localizedReason: "show your saved passwords")) == true else { return }
        passwords.reload()
        isUnlocked = true
    }

    private func lock() {
        isUnlocked = false
        revealed = [:]
        query = ""
    }

    /// Marked as concealed, so clipboard managers that respect it don't keep the password.
    private func copy(_ account: SavedPassword) {
        guard let password = passwords.password(for: account) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(password, forType: .string)
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
    }
}

private struct AppearanceSettings: View {
    @Environment(ProfilePreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        @Bindable var appearance = preferences.appearance
        Form {
            Picker("Profile theme", selection: $appearance.selection) {
                ForEach(BrowserAppearance.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .help("System follows your Mac’s appearance.")
            Toggle(isOn: $appearance.usesSeparatePageTheme) {
                Text("Use a separate theme for websites")
                Text("When off, websites follow Lisière’s theme.")
            }
            .toggleStyle(.switch)
            .accessibilityLabel("Use a separate theme for websites")
            .accessibilityHint("When off, websites follow Lisière’s theme.")
            if appearance.usesSeparatePageTheme {
                Picker("Website theme", selection: $appearance.pageSelection) {
                    ForEach(WebPageAppearance.separateChoices) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
            }
            Text("Websites use this preference when they support it. Their colors aren’t forced.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker("Tabs", selection: $preferences.tabLayout) {
                ForEach(TabLayout.allCases) { layout in
                    Text(layout.title).tag(layout)
                }
            }
            Picker("Bookmarks bar", selection: $preferences.bookmarksBarVisibility) {
                ForEach(BookmarksBarVisibility.allCases) { visibility in
                    Text(visibility.title).tag(visibility)
                }
            }

            Section {
                Picker("Mascot colors", selection: $preferences.mascotPalette) {
                    ForEach(MascotPalette.allCases) { palette in
                        Text(palette.title).tag(palette)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(Mascot.allCases) { choice in
                        Button {
                            preferences.mascot = choice
                        } label: {
                            VStack(spacing: 8) {
                                Image(choice.iconName(for: preferences.mascotPalette))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 64, height: 64)
                                HStack(spacing: 5) {
                                    Image(systemName: preferences.mascot == choice ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(preferences.mascot == choice ? Color.accentColor : Color.secondary)
                                    Text(choice.title)
                                }
                                .font(.callout)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .background(preferences.mascot == choice ? Color.accentColor.opacity(0.08) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(preferences.mascot == choice ? Color.accentColor : Color.primary.opacity(0.12),
                                              lineWidth: 1)
                        }
                        .accessibilityLabel("\(choice.title), \(preferences.mascotPalette.title)")
                        .accessibilityValue(preferences.mascot == choice ? "Selected" : "Not selected")
                        .accessibilityAddTraits(preferences.mascot == choice ? [.isSelected] : [])
                        .help("Use \(choice.title) on the start page and in the Dock")
                    }
                }
            } header: {
                Text("Mascot & Dock Icon")
            } footer: {
                Text("Your choice appears on the start page and in the Dock while Lisière is running. "
                     + "Finder keeps the Lutin icon.")
            }
        }
        .onChange(of: preferences.mascot) { _, choice in choice.applyDockIcon(palette: preferences.mascotPalette) }
        .onChange(of: preferences.mascotPalette) { _, palette in preferences.mascot.applyDockIcon(palette: palette) }
    }
}

private struct PrivacySettings: View {
    let browsingData: BrowsingData
    let contentBlocker: ContentBlocker
    let profileName: String?
    @State private var isShowingClearData = false
    @State private var query = ""
    @State private var isConfirmingRemoveAll = false

    private var records: [WKWebsiteDataRecord] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return browsingData.siteRecords }
        return browsingData.siteRecords.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { contentBlocker.isEnabled }, set: { contentBlocker.setEnabled($0) })) {
                    Text("Block trackers")
                    Text("Stops known tracking and advertising services from loading on other sites. "
                         + "You can turn it off for a site from the shield in the address bar.")
                }
                LabeledContent("History and website data") {
                    Button("Clear…") { isShowingClearData = true }
                }
            }

            Section {
                TextField("Search", text: $query, prompt: Text("Search Sites"))
                    .labelsHidden()
                if !browsingData.hasLoadedSiteRecords {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if records.isEmpty {
                    Text(query.isEmpty ? "No websites have stored data." : "No sites match “\(query)”.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(records, id: \.displayName) { record in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.displayName)
                                Text(BrowsingData.summary(of: record))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove") {
                                Task { await browsingData.removeData(for: [record]) }
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Website Data")
                    Spacer()
                    Button("Remove All") { isConfirmingRemoveAll = true }
                        .disabled(browsingData.siteRecords.isEmpty)
                }
            }
        }
        .task { await browsingData.loadSiteRecords() }
        .sheet(isPresented: $isShowingClearData) {
            ClearDataView(data: browsingData, profileName: profileName)
        }
        .confirmationDialog("Remove data stored by all websites?", isPresented: $isConfirmingRemoveAll) {
            Button("Remove All", role: .destructive) {
                Task { await browsingData.removeData(for: browsingData.siteRecords) }
            }
        } message: {
            Text("This signs you out of most websites, and can’t be undone.")
        }
    }
}

private struct SiteSettings: View {
    let contentBlocker: ContentBlocker
    let sitePermissions: SitePermissions
    let zoomLevels: ZoomStore

    var body: some View {
        Form {
            Section {
                let sites = sitePermissions.mediaDecisions
                if sites.isEmpty {
                    Text("No sites have asked to use the camera or microphone.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sites) { site in
                    HStack {
                        Text(site.site)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        permissionPicker("Camera", .camera, current: site.camera, site: site.site)
                        permissionPicker("Microphone", .microphone, current: site.microphone, site: site.site)
                        removeButton { sitePermissions.removeDecisions(on: site.site) }
                    }
                }
            } header: {
                sectionHeader("Camera and Microphone", isEmpty: sitePermissions.mediaDecisions.isEmpty) {
                    sitePermissions.removeAllMediaDecisions()
                }
            } footer: {
                Text("Private windows ask again, and forget the answers when they close.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                let levels = zoomLevels.levelsByHost.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
                if levels.isEmpty {
                    Text("Sites you zoom in or out on are remembered here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(levels, id: \.key) { host, level in
                    HStack {
                        Text(host)
                        Spacer()
                        Text(level, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        removeButton { zoomLevels.setLevel(1, for: host) }
                    }
                }
            } header: {
                sectionHeader("Page Zoom", isEmpty: zoomLevels.levelsByHost.isEmpty) { zoomLevels.removeAll() }
            }

            Section {
                if contentBlocker.exceptions.isEmpty {
                    Text("Trackers are blocked on every site.")
                        .foregroundStyle(.secondary)
                }
                ForEach(contentBlocker.exceptions, id: \.self) { site in
                    HStack {
                        Text(site)
                        Spacer()
                        removeButton { Task { await contentBlocker.removeException(site) } }
                    }
                }
            } header: {
                sectionHeader("Tracker Blocking Turned Off", isEmpty: contentBlocker.exceptions.isEmpty) {
                    Task { await contentBlocker.removeAllExceptions() }
                }
            }
        }
    }

    private func permissionPicker(_ title: String, _ permission: SitePermissions.Permission, current: Bool?,
                                  site: String) -> some View {
        Picker(title, selection: Binding(get: { current },
                                         set: { sitePermissions.setDecision($0, for: permission, on: site) })) {
            Text("Ask").tag(Bool?.none)
            Text("Allow").tag(Bool?.some(true))
            Text("Don’t Allow").tag(Bool?.some(false))
        }
        .fixedSize()
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "minus.circle")
        }
        .buttonStyle(.borderless)
        .help("Reset")
    }

    private func sectionHeader(_ title: String, isEmpty: Bool, resetAll: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button("Reset All", action: resetAll)
                .disabled(isEmpty)
        }
    }
}

private struct DownloadSettings: View {
    @Environment(ProfilePreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Toggle(isOn: $preferences.asksWhereToSave) {
                Text("Ask where to save each download")
                Text("When off, downloads save to the Downloads folder.")
            }
        }
    }
}
