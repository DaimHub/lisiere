import AppKit
import SwiftUI

/// AppKit owns native row dragging, insertion indicators, autoscroll and group drop targets.
struct ToolbarOutlineView: NSViewRepresentable {
    @Binding var layout: BrowserToolbarLayout

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView(frame: NSRect(x: 0, y: 0, width: 620, height: 300))
        outline.autoresizingMask = [.width]
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("toolbar"))
        column.resizingMask = .autoresizingMask
        column.width = 600
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowHeight = 36
        outline.intercellSpacing = NSSize(width: 0, height: 2)
        outline.indentationPerLevel = 18
        outline.style = .inset
        outline.draggingDestinationFeedbackStyle = .gap
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.allowsMultipleSelection = false
        outline.focusRingType = .none
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.registerForDraggedTypes([Coordinator.dragType])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.setDraggingSourceOperationMask([], forLocal: false)
        outline.setAccessibilityLabel("Toolbar buttons and groups")
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        context.coordinator.outline = outline
        context.coordinator.reload(layout)
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.current != layout { context.coordinator.reload(layout) }
    }

    @MainActor
    final class Node: NSObject {
        let id: String
        var entry: ToolbarEntry
        var parentID: String?
        var children: [Node] = []
        init(id: String, entry: ToolbarEntry, parentID: String? = nil) {
            self.id = id; self.entry = entry; self.parentID = parentID
        }
        var isGroup: Bool { parentID == nil && entry.isGroup }
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        static let dragType = NSPasteboard.PasteboardType("io.github.daimhub.lisiere.toolbar-row")
        var parent: ToolbarOutlineView
        weak var outline: NSOutlineView?
        var current: BrowserToolbarLayout?
        var roots: [Node] = []
        var nodes: [String: Node] = [:]
        init(_ parent: ToolbarOutlineView) { self.parent = parent }

        func reload(_ layout: BrowserToolbarLayout) {
            let selectedID = outline.flatMap { $0.item(atRow: $0.selectedRow) as? Node }?.id
            current = layout
            var next: [String: Node] = [:]
            func node(_ entry: ToolbarEntry, parentID: String? = nil) -> Node {
                let value = nodes[entry.id] ?? Node(id: entry.id, entry: entry)
                value.entry = entry
                value.parentID = parentID
                value.children = []
                next[value.id] = value
                return value
            }
            roots = layout.entries.map { entry in
                let root = node(entry)
                if entry.isGroup { root.children = entry.items.map { node(ToolbarEntry($0), parentID: entry.id) } }
                return root
            }
            nodes = next
            outline?.reloadData()
            outline?.expandItem(nil, expandChildren: true)
            if let selectedID, let selected = nodes[selectedID], let outline {
                let row = outline.row(forItem: selected)
                if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
            }
        }
        func change(_ action: (inout BrowserToolbarLayout) -> Void) {
            var value = parent.layout
            action(&value)
            parent.layout = value
        }
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            (item as? Node)?.children.count ?? roots.count
        }
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            ((item as? Node)?.children ?? roots)[index]
        }
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? Node)?.isGroup == true }
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? Node else { return nil }
            let cell = (outlineView.makeView(withIdentifier: ToolbarRowCell.reuseID, owner: nil) as? ToolbarRowCell)
                ?? ToolbarRowCell()
            cell.configure(node, coordinator: self)
            return cell
        }
        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard let node = item as? Node else { return nil }
            let writer = NSPasteboardItem()
            writer.setString(node.id, forType: Self.dragType)
            return writer
        }
        private func draggedID(_ info: NSDraggingInfo) -> String? {
            guard let source = info.draggingSource as? NSOutlineView, source === outline,
                  let id = info.draggingPasteboard.string(forType: Self.dragType), nodes[id] != nil else { return nil }
            return id
        }
        func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo,
                         proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
            guard let id = draggedID(info) else { return [] }
            if let target = item as? Node {
                guard id != target.id, nodes[id]?.children.contains(where: { $0.id == target.id }) != true else { return [] }
                if !target.isGroup, index != NSOutlineViewDropOnItemIndex { return [] }
                // A drop on an existing child inserts beside it in that child's group.
                if let parentID = target.parentID, let parent = nodes[parentID],
                   let child = parent.children.firstIndex(where: { $0.id == target.id }) {
                    outlineView.setDropItem(parent, dropChildIndex: child + 1)
                }
            }
            return .move
        }
        func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo,
                         item: Any?, childIndex index: Int) -> Bool {
            guard let id = draggedID(info) else { return false }
            let target = item as? Node
            if let target, !target.isGroup {
                change { $0.group(id, with: target.id) }
            } else {
                let position = index == NSOutlineViewDropOnItemIndex ? (target?.children.count ?? roots.count) : index
                change { $0.move(id, toGroup: target?.id, at: position) }
            }
            return true
        }

        func groupingMenu(for node: Node) -> NSMenu {
            let menu = NSMenu()
            for target in roots where target.id != node.id && target.id != node.parentID {
                let item = ToolbarMenuItem(title: "Group with \(target.entry.title)") { [weak self] in
                    self?.change { $0.group(node.id, with: target.id) }
                }
                item.image = NSImage(systemSymbolName: target.isGroup ? "rectangle.3.group" : target.entry.items[0].symbol,
                                     accessibilityDescription: nil)
                menu.addItem(item)
            }
            if node.isGroup {
                menu.addItem(.separator())
                menu.addItem(ToolbarMenuItem(title: "Separate All Buttons") { [weak self] in self?.change { $0.ungroup(node.id) } })
            } else if let item = node.entry.items.first, node.parentID != nil {
                menu.addItem(.separator())
                menu.addItem(ToolbarMenuItem(title: "Move Out of Group") { [weak self] in self?.change { $0.separate(item) } })
            }
            return menu
        }
    }
}

@MainActor
private final class ToolbarRowCell: NSTableCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("ToolbarRow")
    private let handle = NSImageView()
    private let symbol = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let up = ToolbarActionButton()
    private let down = ToolbarActionButton()
    private let group = ToolbarActionButton()
    private let separate = ToolbarActionButton()
    private let remove = ToolbarActionButton()

    init() {
        super.init(frame: .zero)
        identifier = Self.reuseID
        handle.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "Drag to reorder")
        handle.contentTintColor = .tertiaryLabelColor
        handle.toolTip = "Drag between rows to reorder, or onto a row to group"
        symbol.contentTintColor = .controlAccentColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // AppKit derives the native drag image from these outlets.
        textField = label
        imageView = symbol
        for (button, name) in [(up, "chevron.up"), (down, "chevron.down"), (group, "link"),
                               (separate, "rectangle.split.3x1"), (remove, "minus.circle")] {
            button.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.imagePosition = .imageOnly
            button.contentTintColor = .secondaryLabelColor
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }
        let stack = NSStackView(views: [handle, symbol, label, up, down, group, separate, remove])
        stack.orientation = .horizontal
        stack.distribution = .fill
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            handle.widthAnchor.constraint(equalToConstant: 14), symbol.widthAnchor.constraint(equalToConstant: 20)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Only update values and handlers: keep controls, images and Auto Layout constraints reusable during dragging.
    func configure(_ node: ToolbarOutlineView.Node, coordinator: ToolbarOutlineView.Coordinator) {
        symbol.image = NSImage(systemSymbolName: node.isGroup ? "rectangle.3.group" : node.entry.items[0].symbol,
                               accessibilityDescription: nil)
        label.stringValue = node.entry.title
        label.font = .systemFont(ofSize: 13, weight: node.isGroup ? .semibold : .regular)
        label.toolTip = node.entry.title
        let siblings = coordinator.parent.layout.siblings(of: node.id)
        configure(up, "Move \(node.entry.title) Left", enabled: siblings.first != node.id) { [weak coordinator] in
            coordinator?.change { $0.move(node.id, by: -1) }
        }
        configure(down, "Move \(node.entry.title) Right", enabled: siblings.last != node.id) { [weak coordinator] in
            coordinator?.change { $0.move(node.id, by: 1) }
        }
        configure(group, "Group \(node.entry.title) with…") { [weak coordinator, weak group] in
            guard let coordinator, let group else { return }
            coordinator.groupingMenu(for: node).popUp(positioning: nil, at: NSPoint(x: 0, y: group.bounds.height), in: group)
        }
        configure(separate, node.isGroup ? "Separate All Buttons" : "Move Out of Group",
                  enabled: node.isGroup || node.parentID != nil) { [weak coordinator] in
            coordinator?.change { layout in
                if node.isGroup { layout.ungroup(node.id) }
                else if let item = node.entry.items.first { layout.separate(item) }
            }
        }
        configure(remove, "Remove \(node.entry.title)", enabled: !node.isGroup && node.entry.items.first?.isRequired == false) { [weak coordinator] in
            if let item = node.entry.items.first { coordinator?.change { $0.remove(item) } }
        }
    }
    private func configure(_ button: ToolbarActionButton, _ label: String, enabled: Bool = true,
                           action: @escaping @MainActor () -> Void) {
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.isEnabled = enabled
        button.actionHandler = action
    }
}

@MainActor
private final class ToolbarActionButton: NSButton {
    var actionHandler: (@MainActor () -> Void)?
    init() { super.init(frame: .zero); target = self; action = #selector(invoke) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { actionHandler?() }
}

@MainActor
private final class ToolbarMenuItem: NSMenuItem {
    let actionHandler: @MainActor () -> Void
    init(title: String, action: @escaping @MainActor () -> Void) {
        actionHandler = action
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { actionHandler() }
}
