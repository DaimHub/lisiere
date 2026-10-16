import SwiftUI

struct ToolbarSettings: View {
    @Bindable var preferences: ProfilePreferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Customize Toolbar")
                    .font(.title2.weight(.semibold))
                Text("Use the arrows to change the order of items for this profile.")
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(preferences.toolbarLayout.items) { item in
                            previewItem(item)
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.automatic)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Toolbar preview")
            }
            .padding(20)

            List {
                Section("Shown in Toolbar") {
                    ForEach(preferences.toolbarLayout.items) { item in
                        itemRow(item)

                    }

                }
                if !preferences.toolbarLayout.availableItems.isEmpty {
                    Section("Add Buttons") {
                        ForEach(preferences.toolbarLayout.availableItems) { item in
                            HStack {
                                Label(item.title, systemImage: item.symbol)
                                Spacer()
                                Button("Add", systemImage: "plus") {
                                    preferences.toolbarLayout.add(item)
                                }
                                .labelStyle(.titleAndIcon)
                                .accessibilityLabel("Add \(item.title)")
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 4)
                            .accessibilityElement(children: .contain)
                            .accessibilityAction(named: Text("Add \(item.title)")) {
                                preferences.toolbarLayout.add(item)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            Divider()
            HStack {
                Button("Restore Default") { preferences.toolbarLayout = .standard }
                    .disabled(preferences.toolbarLayout == .standard)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 540, height: 620)
    }

    private func itemRow(_ item: BrowserToolbarItem) -> some View {
        HStack(spacing: 10) {
            Label(item.title, systemImage: item.symbol)
            Spacer()
            Button { preferences.toolbarLayout.move(item, by: -1) } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(preferences.toolbarLayout.items.first == item)
            .help("Move \(item.title) Left")
            .accessibilityLabel("Move \(item.title) Left")
            Button { preferences.toolbarLayout.move(item, by: 1) } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(preferences.toolbarLayout.items.last == item)
            .help("Move \(item.title) Right")
            .accessibilityLabel("Move \(item.title) Right")
            Button { preferences.toolbarLayout.remove(item) } label: {
                Image(systemName: "minus.circle")
            }
            .disabled(item.isRequired)
            .help(item.isRequired ? "\(item.title) stays in the toolbar" : "Remove \(item.title)")
            .accessibilityLabel("Remove \(item.title)")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            Button("Move \(item.title) Left") { preferences.toolbarLayout.move(item, by: -1) }
            Button("Move \(item.title) Right") { preferences.toolbarLayout.move(item, by: 1) }
            if !item.isRequired {
                Button("Remove \(item.title)") { preferences.toolbarLayout.remove(item) }
            }
        }
    }

    private func previewItem(_ item: BrowserToolbarItem) -> some View {
        Group {
            if item == .address {
                Label("Address", systemImage: item.symbol)
                    .frame(width: 110)
            } else if item == .navigation {
                HStack(spacing: 14) {
                    Image(systemName: "chevron.left")
                    Image(systemName: "chevron.right")
                    Image(systemName: "arrow.clockwise")
                }
                .padding(.horizontal, 10)
            } else {
                Image(systemName: item.symbol).frame(width: 34)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .frame(height: BrowserChrome.navigationControlHeight)
        .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
        .help(item.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
    }
}

/// Shared geometry for single controls and the navigation group.
extension View {
    func toolbarControlBackground() -> some View {
        padding(2)
            .background(Color.primary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct ToolbarProfileLabelStyle: LabelStyle {
    let compact: Bool
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
            if !compact { configuration.title }
        }
    }
}
