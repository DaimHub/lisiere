import SwiftUI

struct ToolbarSettings: View {
    @Bindable var preferences: ProfilePreferences
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID = BrowserToolbarItem.profile.rawValue

    private var selection: ToolbarEntry? {
        if let entry = preferences.toolbarLayout.entries.first(where: { $0.id == selectedID }) { return entry }
        return preferences.toolbarLayout.items.first(where: { $0.rawValue == selectedID }).map(ToolbarEntry.init)
    }

    private var selectedParent: ToolbarEntry? {
        preferences.toolbarLayout.entries.first { $0.isGroup && $0.items.contains { $0.rawValue == selectedID } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Customize Toolbar").font(.title2.weight(.semibold))
                Text("Select a button or group in the preview, then move it left or right.")
                    .foregroundStyle(.secondary)
                preview
                selectionControls
            }
            .padding(20)
            Divider()
            if !preferences.toolbarLayout.availableItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Add Buttons").font(.headline).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                        ForEach(preferences.toolbarLayout.availableItems) { item in
                            Button {
                                preferences.toolbarLayout.add(item)
                                selectedID = item.rawValue
                            } label: {
                                HStack {
                                    Label(item.title, browserIcon: item.icon)
                                    Spacer()
                                    Image(browserIcon: .add)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .accessibilityLabel("Add \(item.title)")
                        }
                    }
                }
                .padding(20)
            }
            Spacer(minLength: 0)
            Divider()
            HStack {
                Button("Restore Default") {
                    preferences.toolbarLayout = .standard
                    selectedID = BrowserToolbarItem.profile.rawValue
                }
                .disabled(preferences.toolbarLayout == .standard)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                    .tint(preferences.accentColor)
            }
            .padding(20)
        }
        .frame(width: 620, height: 520)
        // Native secondary controls stay legible with any custom profile accent.
        .tint(nil)
    }

    private var preview: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(preferences.toolbarLayout.entries) { entry in
                        HStack(spacing: 0) {
                            if entry.isGroup {
                                previewButton(id: entry.id, title: entry.title) {
                                    Image(browserIcon: .group).frame(width: 28)
                                }
                                Divider().frame(height: 16).padding(.horizontal, 2)
                            }
                            ForEach(entry.items) { item in
                                previewButton(id: item.rawValue, title: item.title) {
                                    if item == .address {
                                        Label("Address", browserIcon: item.icon).frame(width: 110)
                                    } else {
                                        Image(browserIcon: item.icon).frame(width: 30)
                                    }
                                }
                            }
                        }
                        .padding(2)
                        .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(selectedID == entry.id ? Color.accentColor : .clear, lineWidth: 2)
                                .allowsHitTesting(false)
                        }
                        .id(entry.id)
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.automatic)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("Toolbar preview")
            .onAppear { proxy.scrollTo(selectedParent?.id ?? selectedID, anchor: .center) }
            .onChange(of: selectedID) { _, _ in
                proxy.scrollTo(selectedParent?.id ?? selectedID, anchor: .center)
            }
            .onChange(of: preferences.toolbarLayout) { _, _ in
                if selection == nil { selectedID = preferences.toolbarLayout.entries.first?.id ?? "profile" }
                proxy.scrollTo(selectedParent?.id ?? selectedID, anchor: .center)
            }
        }
    }

    private func previewButton<Content: View>(id: String, title: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        Button { selectedID = id } label: {
            content()
                .font(.system(size: 12, weight: .medium))
                .frame(height: BrowserChrome.navigationControlHeight)
                .background(selectedID == id ? Color.accentColor.opacity(0.18) : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("Select \(title)")
        .accessibilityLabel("Select \(title)")
        .accessibilityAddTraits(selectedID == id ? .isSelected : [])
    }

    @ViewBuilder private var selectionControls: some View {
        if let selection {
            let siblings = preferences.toolbarLayout.siblings(of: selectedID)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(selection.title).font(.headline).lineLimit(1).help(selection.title)
                    Spacer()
                    Button("Move Left", browserIcon: .back) { preferences.toolbarLayout.move(selectedID, by: -1) }
                        .disabled(siblings.first == selectedID)
                        .keyboardShortcut(.leftArrow, modifiers: .option)
                        .accessibilityLabel("Move \(selection.title) Left")
                    Button("Move Right", browserIcon: .forward) { preferences.toolbarLayout.move(selectedID, by: 1) }
                        .disabled(siblings.last == selectedID)
                        .keyboardShortcut(.rightArrow, modifiers: .option)
                        .accessibilityLabel("Move \(selection.title) Right")
                }
                HStack(spacing: 12) {
                    Menu("Group with…", browserIcon: .link) {
                        BrowserMenuContent(actions: groupingActions)
                    }
                    .browserMenu { groupingActions }
                    .disabled(groupingActions.isEmpty)
                    Button(selection.isGroup ? "Separate All Buttons" : "Move Out of Group", browserIcon: .ungroup) {
                        if selection.isGroup {
                            preferences.toolbarLayout.ungroup(selectedID)
                            selectedID = selection.items[0].rawValue
                        } else { preferences.toolbarLayout.separate(selection.items[0]) }
                    }
                    .disabled(!selection.isGroup && selectedParent == nil)
                    Button("Remove", browserIcon: .remove) { preferences.toolbarLayout.remove(selection.items[0]) }
                        .disabled(selection.isGroup || selection.items[0].isRequired)
                }
                Text(selectedParent == nil ? "Move the selection in the toolbar." : "Move this button within its group, or separate it first.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .controlSize(.small)
        }
    }

    private var groupingActions: [BrowserContextAction] {
        guard preferences.toolbarLayout.canGroup(selectedID) else { return [] }
        return preferences.toolbarLayout.entries.filter {
            $0.id != selectedID && $0.id != selectedParent?.id && $0.items.allSatisfy(\.canGroup)
        }.map { target in
            BrowserContextAction(title: "Group with \(target.title)",
                                 icon: target.isGroup ? .group : target.items[0].icon) {
                preferences.toolbarLayout.group(selectedID, with: target.id)
                if let item = target.items.first, let group = preferences.toolbarLayout.entry(containing: item) {
                    selectedID = group.id
                }
            }
        }
    }
}

/// Shared geometry for single controls and user-defined groups.
extension View {
    func toolbarControlBackground() -> some View {
        padding(2)
            .background(Color.primary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
