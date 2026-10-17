import SwiftUI
import UniformTypeIdentifiers

/// A flat, stable set of SwiftUI rows keeps drag sources alive when buttons change groups.
struct ToolbarOutlineView: View {
    @Binding var layout: BrowserToolbarLayout
    @State private var draggedID: String?
    @State private var collapsedGroups: Set<String> = []
    private static let dragType = UTType(exportedAs: "io.github.daimhub.lisiere.toolbar-row")

    private struct Row: Identifiable {
        let entry: ToolbarEntry
        var parentID: String? = nil
        var id: String { entry.id }
    }

    private var rows: [Row] {
        layout.entries.flatMap { entry in
            [Row(entry: entry)] + (entry.isGroup && !collapsedGroups.contains(entry.id)
                ? entry.items.map { Row(entry: ToolbarEntry($0), parentID: entry.id) } : [])
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(rows) { row in
                    rowView(row)
                        .onDrag {
                            draggedID = row.id
                            let provider = NSItemProvider()
                            provider.registerDataRepresentation(forTypeIdentifier: Self.dragType.identifier,
                                                                visibility: .ownProcess) { completion in
                                completion(Data(row.id.utf8), nil)
                                return nil
                            }
                            return provider
                        }
                        .onDrop(of: [Self.dragType], delegate: dropDelegate(target: row.id))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .onDrop(of: [Self.dragType], delegate: dropDelegate(target: nil))
        .accessibilityLabel("Toolbar buttons and groups")
        .onDisappear { draggedID = nil }
    }

    private func dropDelegate(target: String?) -> ReorderDropDelegate<String> {
        ReorderDropDelegate(targetID: target, draggedID: $draggedID,
                            canMove: { !layout.siblings(of: $0).isEmpty },
                            move: { id, target in layout.move(id, over: target) })
    }

    private func rowView(_ row: Row) -> some View {
        let entry = row.entry
        let siblings = layout.siblings(of: row.id)
        return HStack(spacing: 8) {
            if entry.isGroup {
                Button {
                    if !collapsedGroups.insert(row.id).inserted { collapsedGroups.remove(row.id) }
                } label: {
                    Image(browserIcon: .chevronDown, size: 12)
                        .rotationEffect(.degrees(collapsedGroups.contains(row.id) ? -90 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(collapsedGroups.contains(row.id) ? "Expand" : "Collapse") \(entry.title)")
                .frame(width: 14)
            } else {
                Color.clear.frame(width: 14)
            }
            Image(browserIcon: .drag, size: 14).foregroundStyle(.tertiary)
                .help("Drag to reorder")
            Image(browserIcon: entry.isGroup ? .group : entry.items[0].icon, size: 16)
                .foregroundStyle(Color.accentColor).frame(width: 20)
            Text(entry.title)
                .font(.system(size: 13, weight: entry.isGroup ? .semibold : .regular))
                .lineLimit(1).help(entry.title)
                .frame(maxWidth: .infinity, alignment: .leading)
            action(.chevronUp, "Move \(entry.title) Up", enabled: siblings.first != row.id) {
                layout.move(row.id, by: -1)
            }
            action(.chevronDown, "Move \(entry.title) Down", enabled: siblings.last != row.id) {
                layout.move(row.id, by: 1)
            }
            Menu {
                BrowserMenuContent(actions: groupingActions(for: row))
            } label: {
                Image(browserIcon: .link, size: 14).frame(width: 24, height: 28)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .browserMenu { groupingActions(for: row) }
            .disabled(!layout.canGroup(row.id))
            .help("Group \(entry.title) with…")
            .accessibilityLabel("Group \(entry.title) with…")
            action(.ungroup, entry.isGroup ? "Separate All Buttons" : "Move Out of Group",
                   enabled: entry.isGroup || row.parentID != nil) {
                if entry.isGroup { layout.ungroup(row.id) }
                else { layout.separate(entry.items[0]) }
            }
            action(.remove, "Remove \(entry.title)", enabled: !entry.isGroup && !entry.items[0].isRequired) {
                layout.remove(entry.items[0])
            }
        }
        .padding(.leading, row.parentID == nil ? 0 : 18)
        .padding(.horizontal, 4)
        .frame(height: 36)
        .contentShape(Rectangle())
    }

    private func action(_ icon: BrowserIcon, _ title: String, enabled: Bool,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(browserIcon: icon, size: 14).frame(width: 24, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(!enabled)
        .help(title)
        .accessibilityLabel(title)
    }

    private func groupingActions(for row: Row) -> [BrowserContextAction] {
        guard layout.canGroup(row.id) else { return [] }
        var actions = layout.entries.filter {
            $0.id != row.id && $0.id != row.parentID && $0.items.allSatisfy(\.canGroup)
        }.map { target in
            BrowserContextAction(title: "Group with \(target.title)",
                                 icon: target.isGroup ? .group : target.items[0].icon) {
                layout.group(row.id, with: target.id)
            }
        }
        if row.entry.isGroup {
            actions += [.separator, .init(title: "Separate All Buttons", icon: .ungroup) { layout.ungroup(row.id) }]
        } else if row.parentID != nil {
            actions += [.separator, .init(title: "Move Out of Group", icon: .ungroup) { layout.separate(row.entry.items[0]) }]
        }
        return actions
    }
}
