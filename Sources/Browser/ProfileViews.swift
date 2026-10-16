import SwiftUI

/// The existing browser chrome, bound to one profile for the window's entire lifetime.
struct ProfileBrowserWindow: View {
    let profiles: ProfileStore
    let profileID: UUID
    var isPrivate = false
    @State private var browser: BrowserModel?

    var body: some View {
        if let context = profiles.context(for: profileID) {
            Group {
                if let browser {
                    BrowserWindow(bookmarks: context.bookmarks, context: context, profiles: profiles, browser: browser)
                        .environment(context.browsingData)
                        .environment(context.preferences)
                        .environment(context.favicons)
                } else {
                    Color.clear
                }
            }
            .onAppear {
                // Construct once after SwiftUI installs State. Eager State(initialValue:) creates spare
                // models/web views on every profile rename or selection and can keep stores alive.
                if browser == nil { browser = context.makeBrowser(isPrivate: isPrivate) }
            }
        } else {
            ContentUnavailableView("Profile Unavailable", systemImage: "person.crop.circle.badge.exclamationmark",
                                   description: Text(profiles.loadError ?? "This profile was deleted or is waiting for deletion."))
        }
    }
}

struct ProfileSettings: View {
    let profiles: ProfileStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Profile", selection: Binding(get: { profiles.selectedID }, set: { id in
                    do { try profiles.select(id) } catch { profiles.errorMessage = error.localizedDescription }
                })) {
                    ForEach(profiles.availableProfiles) { profile in Text(profile.name).tag(profile.id) }
                }
                Button("Manage Profiles…") { openWindow(id: BrowserApp.profilesWindowID) }
            }
            .padding()
            Divider()
            if let context = profiles.context(for: profiles.selectedID) {
                SettingsView(profileID: context.id, profileName: profiles.name(context.id), browsingData: context.browsingData, contentBlocker: context.contentBlocker,
                             sitePermissions: context.sitePermissions, zoomLevels: context.zoomLevels,
                             passwords: context.passwords, passkeys: .shared, updater: .shared)
                    .environment(context.preferences)
                    .environment(context.favicons)
            } else {
                Text(profiles.loadError ?? "Select a profile.").padding()
            }
        }
        .frame(width: 580)
    }
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
                                .help("Open or switch to this profile’s window")
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
                Text("Themes, the mascot and Dock icon, passkeys, the default browser and app updates apply across profiles. Downloaded files stay where you saved them.")
                Text("Private windows use fresh temporary website data. They never save history or passwords and never reopen with a session. Bookmarks and downloads stay in the originating profile.")
            }
            if let error = profiles.loadError {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 480)
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
