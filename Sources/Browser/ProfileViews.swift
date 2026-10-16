import SwiftUI

/// The scene owns its physical window while each profile retains separate browser state.
struct ProfileBrowserWindow: View {
    let profiles: ProfileStore
    let profileID: UUID
    var isPrivate = false
    @State private var owner: ProfileWindowController?
    @State private var isFullScreen = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let owner, let id = owner.browser.profileID, let context = profiles.context(for: id) {
                BrowserWindow(bookmarks: context.bookmarks, context: context, profiles: profiles,
                              browser: owner.browser, isFullScreen: isFullScreen)
                    .id(id)
                    .environment(context.browsingData)
                    .environment(context.preferences)
                    .environment(context.favicons)
            } else if profiles.context(for: profileID) == nil {
                ContentUnavailableView("Profile Unavailable", systemImage: "person.crop.circle.badge.exclamationmark",
                                       description: Text(profiles.loadError ?? "This profile is unavailable."))
            } else {
                Color.clear
            }
        }
        .background {
            if let owner {
                WindowChromeConfigurator(
                    titlebarHeight: BrowserChrome.titlebarHeight(for: owner.browser.preferences.tabLayout),
                    isFullScreen: $isFullScreen, onWindowChange: owner.connect, onClose: owner.close)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard let owner, let window = notification.object as? NSWindow, window === owner.window else { return }
            owner.becameKey()
        }
        .onAppear {
            guard owner == nil else { return }
            do {
                // Construct only after SwiftUI installs State; body recomputation must not create WebViews.
                let controller = try ProfileWindowController(profiles: profiles, profileID: profileID, isPrivate: isPrivate)
                controller.onActivate = { browser in
                    ExternalURLRouter.shared.register(browser, openWindow: openWindow)
                }
                owner = controller
                controller.onActivate?(controller.browser)
                for _ in 0..<controller.additionalWindows {
                    openWindow(id: BrowserApp.windowID, value: ProfileWindowRequest(profileID: profileID))
                }
                if !isPrivate { profiles.restoreOtherProfiles(except: profileID, openWindow: openWindow) }
            } catch { profiles.errorMessage = error.localizedDescription }
        }
    }
}

struct ProfileSettings: View {
    let profiles: ProfileStore
    var body: some View { SettingsView(profiles: profiles, passkeys: .shared, updater: .shared) }
}

struct ProfilesView: View {
    let profiles: ProfileStore
    @Environment(\.openWindow) private var openWindow
    private struct EditorRequest: Identifiable {
        let id = UUID()
        let profile: BrowserProfile?
    }
    @State private var editor: EditorRequest?
    @State private var removing: BrowserProfile?

    var body: some View {
        Form {
            Section {
                ForEach(profiles.profiles) { profile in
                    HStack {
                        Label(profile.name, systemImage: profile.icon.rawValue)
                            .lineLimit(1)
                            .help(profile.name)
                        Spacer()
                        if profile.pendingDeletion {
                            Text("Deletion incomplete").foregroundStyle(.secondary)
                        } else {
                            Button("Open") { profiles.activate(profile.id, openWindow: openWindow) }
                                .help("Use this profile in the last active browser window")
                            Button("Edit…") { editor = EditorRequest(profile: profile) }
                        }
                        Button(profile.pendingDeletion ? "Retry Delete…" : "Delete…", role: .destructive) {
                            removing = profile
                        }
                        .disabled(profiles.availableProfiles.filter { $0.id != profile.id }.isEmpty)
                    }
                }
                Button("New Profile…", systemImage: "plus") { editor = EditorRequest(profile: nil) }
            } header: {
                Text("Profiles")
            } footer: {
                Text("Sign-ins, website data, history, tabs, bookmarks, saved passwords, downloads and settings stay separate. Swipe horizontally with two fingers over the tabs to switch profiles.")
            }
            Section("Outside Profiles") {
                Text("Passkeys, the default browser and app updates are managed by macOS or the app. Downloaded files stay where you saved them.")
                Text("Private windows use fresh temporary website data. They never save history or passwords and never reopen with a session. Bookmarks and downloads stay in the originating profile.")
            }
            if let error = profiles.loadError {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(profiles.deletingID != nil || profiles.loadError != nil)
        .overlay {
            if profiles.deletingID != nil {
                ProgressView("Deleting profile…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .sheet(item: $editor) { request in
            ProfileNameEditor(profile: request.profile, profiles: profiles)
        }
        .confirmationDialog("Delete “\(removing?.name ?? "")”?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible,
                            presenting: removing) { profile in
            Button("Delete Profile", role: .destructive) {
                Task {
                    do { try await profiles.delete(profile.id) }
                    catch { profiles.errorMessage = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { profile in
            Text("Permanently deletes this profile’s website data, history, tabs, bookmarks, saved passwords and settings. This cannot be undone. Downloaded files are kept. Close this profile’s windows and finish or cancel its downloads first.")
        }
        .alert("Profile Could Not Be Changed", isPresented: Binding(
            get: { profiles.errorMessage != nil && editor == nil },
            set: { if !$0 { profiles.errorMessage = nil } })) {
            Button("OK") { profiles.errorMessage = nil }
        } message: { Text(profiles.errorMessage ?? "") }
    }

}

/// Separate identity and local input state keep Create and Rename sheets from reusing a stale presentation.
private struct ProfileNameEditor: View {
    let profile: BrowserProfile?
    let profiles: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var icon: ProfileIcon
    @State private var sourceID: UUID?
    @State private var errorMessage: String?

    init(profile: BrowserProfile?, profiles: ProfileStore) {
        self.profile = profile
        self.profiles = profiles
        _name = State(initialValue: profile?.name ?? "")
        _icon = State(initialValue: profile?.icon ?? .person)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(profile == nil ? "New Profile" : "Edit Profile").font(.headline)
            TextField("Profile name", text: $name).onSubmit(save)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                ForEach(ProfileIcon.allCases) { option in
                    Button { icon = option } label: {
                        Image(systemName: option.rawValue)
                            .font(.system(size: 20))
                            .frame(width: 42, height: 36)
                            .background(icon == option ? Color.accentColor.opacity(0.18) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .help(option.title)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(icon == option ? .isSelected : [])
                }
            }
            if profile == nil {
                Picker("Start with", selection: $sourceID) {
                    Text("Empty profile").tag(Optional<UUID>.none)
                    ForEach(profiles.availableProfiles) { source in
                        Text("Copy from \(source.name)").tag(Optional(source.id))
                    }
                }
                Text(sourceID == nil ? "New sign-ins, empty bookmarks and default settings."
                     : "Copies settings, bookmarks and tab addresses. Sign in again; passwords and history are not copied.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(profile == nil ? "Create Profile" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .alert("Profile Could Not Be Saved", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func save() {
        do {
            if let profile { try profiles.rename(profile.id, to: name, icon: icon) }
            else { _ = try profiles.create(name: name, icon: icon, copying: sourceID) }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
