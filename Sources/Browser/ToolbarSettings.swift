import SwiftUI

struct ToolbarSettings: View {
    @Bindable var preferences: ProfilePreferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Customize Toolbar").font(.title2.weight(.semibold))
                Text("Drag between rows to reorder, or onto a row to group.")
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(preferences.toolbarLayout.entries) { entry in
                            HStack(spacing: 0) {
                                ForEach(entry.items) { item in
                                    if item == .address {
                                        Label("Address", systemImage: item.symbol).frame(width: 110)
                                    } else {
                                        Image(systemName: item.symbol).frame(width: 30)
                                    }
                                }
                            }
                            .font(.system(size: 12, weight: .medium))
                            .frame(height: BrowserChrome.navigationControlHeight)
                            .padding(.horizontal, 2)
                            .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
                            .help(entry.title)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(entry.title)
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.automatic)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Toolbar preview")
            }
            .padding(20)
            HStack {
                Text("Shown in Toolbar").font(.headline)
                Spacer()
                Label("Group", systemImage: "link")
                Label("Separate", systemImage: "rectangle.split.3x1")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            ToolbarOutlineView(layout: $preferences.toolbarLayout)
                .frame(minHeight: 250)
            if !preferences.toolbarLayout.availableItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Add Buttons").font(.headline).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                        ForEach(preferences.toolbarLayout.availableItems) { item in
                            Button {
                                preferences.toolbarLayout.add(item)
                            } label: {
                                HStack {
                                    Label(item.title, systemImage: item.symbol)
                                    Spacer()
                                    Image(systemName: "plus")
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .accessibilityLabel("Add \(item.title)")
                        }
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                Button("Restore Default") { preferences.toolbarLayout = .standard }
                    .disabled(preferences.toolbarLayout == .standard)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 620, height: 720)
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

struct ToolbarProfileLabelStyle: LabelStyle {
    let compact: Bool
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
            if !compact { configuration.title }
        }
    }
}
