import SwiftUI
import WebKit

/// Browser ▸ Settings (⌘,).
struct SettingsView: View {
    let browsingData: BrowsingData
    let contentBlocker: ContentBlocker
    let sitePermissions: SitePermissions
    let zoomLevels: ZoomStore

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "macwindow") }
            PrivacySettings(browsingData: browsingData, contentBlocker: contentBlocker)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            SiteSettings(contentBlocker: contentBlocker, sitePermissions: sitePermissions, zoomLevels: zoomLevels)
                .tabItem { Label("Site Settings", systemImage: "globe") }
            DownloadSettings()
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 500)
    }
}

private struct GeneralSettings: View {
    @AppStorage(SearchEngine.storageKey) private var searchEngine = SearchEngine.google
    @AppStorage(NewTabPage.storageKey) private var newTabPage = NewTabPage.startPage
    @AppStorage(SessionPreferences.restoresWindowsKey) private var restoresWindows = true

    var body: some View {
        Form {
            Picker("Search engine", selection: $searchEngine) {
                ForEach(SearchEngine.allCases) { engine in
                    Text(engine.title).tag(engine)
                }
            }
            Picker("New tabs open with", selection: $newTabPage) {
                ForEach(NewTabPage.allCases) { page in
                    Text(page.title).tag(page)
                }
            }
            Toggle(isOn: $restoresWindows) {
                Text("Reopen windows from last session on launch")
                Text("When off, History ▸ Reopen All Windows from Last Session opens them.")
            }
        }
    }
}

private struct AppearanceSettings: View {
    @AppStorage(TabLayout.storageKey) private var tabLayout = TabLayout.horizontal
    @AppStorage(BookmarksBarVisibility.storageKey) private var bookmarksBarVisibility = BookmarksBarVisibility.always

    var body: some View {
        Form {
            Picker("Tabs", selection: $tabLayout) {
                ForEach(TabLayout.allCases) { layout in
                    Text(layout.title).tag(layout)
                }
            }
            Picker("Bookmarks bar", selection: $bookmarksBarVisibility) {
                ForEach(BookmarksBarVisibility.allCases) { visibility in
                    Text(visibility.title).tag(visibility)
                }
            }
        }
    }
}

private struct PrivacySettings: View {
    let browsingData: BrowsingData
    let contentBlocker: ContentBlocker
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
            ClearDataView(data: browsingData)
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
    @AppStorage(DownloadPreferences.asksWhereToSaveKey) private var asksWhereToSave = false

    var body: some View {
        Form {
            Toggle(isOn: $asksWhereToSave) {
                Text("Ask where to save each download")
                Text("When off, downloads save to the Downloads folder.")
            }
        }
    }
}
