import Foundation

/// Stable action identifiers. Groups are layout entries, never indivisible actions.
enum BrowserToolbarItem: String, CaseIterable, Identifiable {
    case profile, back, forward, reload, address, newTab, home, privateWindow, history, downloads, bookmarks, settings, allActions

    var id: Self { self }
    var isRequired: Bool { self == .profile || self == .address }
    var canGroup: Bool { self != .profile && self != .address }
    var canOverflow: Bool { ![.profile, .back, .forward, .reload, .address, .newTab, .allActions].contains(self) }

    var title: String {
        switch self {
        case .profile: "Profile"
        case .back: "Back"
        case .forward: "Forward"
        case .reload: "Reload"
        case .address: "Address & Search"
        case .newTab: "New Tab"
        case .home: "Home"
        case .privateWindow: "New Private Window"
        case .history: "History"
        case .downloads: "Downloads"
        case .bookmarks: "Bookmarks Bar"
        case .settings: "Settings"
        case .allActions: "All Actions"
        }
    }

    var icon: BrowserIcon {
        switch self {
        case .profile: .profile
        case .back: .back
        case .forward: .forward
        case .reload: .reload
        case .address: .search
        case .newTab: .add
        case .home: .home
        case .privateWindow: .privateWindow
        case .history: .history
        case .downloads: .downloads
        case .bookmarks: .book
        case .settings: .settings
        case .allActions: .more
        }
    }
}

struct ToolbarEntry: Equatable, Identifiable {
    var id: String
    var items: [BrowserToolbarItem]
    var isGroup: Bool { items.count > 1 }
    var title: String {
        isGroup ? "Group: " + items.map(\.title).joined(separator: ", ") : items.first?.title ?? ""
    }
    init(_ item: BrowserToolbarItem) { id = item.rawValue; items = [item] }
    init(id: String = "group.\(UUID().uuidString)", items: [BrowserToolbarItem]) {
        self.id = id
        self.items = items
    }
}

struct BrowserToolbarLayout: Equatable {
    static let legacyStorageKey = "navigationToolbarItems"
    static let storageKey = "navigationToolbarLayoutV2"
    static let standard = Self(entries: [ToolbarEntry(.profile),
        ToolbarEntry(id: "group.navigation", items: [.back, .forward, .reload]),
        ToolbarEntry(.address), ToolbarEntry(.newTab), ToolbarEntry(.allActions)])
    private(set) var entries: [ToolbarEntry]
    var items: [BrowserToolbarItem] { entries.flatMap(\.items) }
    var availableItems: [BrowserToolbarItem] { BrowserToolbarItem.allCases.filter { !items.contains($0) } }

    private struct StoredLayout: Codable {
        var version: Int
        var entries: [StoredEntry]
    }
    private struct StoredEntry: Codable {
        var id: String
        var items: [String]
    }
    var storedValue: Data {
        // This payload contains only strings and integers, so JSON encoding cannot fail.
        try! JSONEncoder().encode(StoredLayout(version: 2, entries: entries.map {
            StoredEntry(id: $0.id, items: $0.items.map(\.rawValue))
        }))
    }

    init(data: Data?, legacyValue: [String]? = nil) {
        if let data, let saved = try? JSONDecoder().decode(StoredLayout.self, from: data), saved.version == 2 {
            let entries = saved.entries.map { ToolbarEntry(id: $0.id, items: $0.items.compactMap(BrowserToolbarItem.init)) }
            if entries.contains(where: { !$0.items.isEmpty }) {
                self.init(entries: entries)
                return
            }
        }
        self.init(legacyValue: legacyValue)
    }

    /// Upgrade the old navigation group in place and preserve every other customized position.
    init(legacyValue: [String]?) {
        var entries = (legacyValue ?? []).compactMap { raw -> ToolbarEntry? in
            if raw == "navigation" { return ToolbarEntry(id: "group.navigation", items: [.back, .forward, .reload]) }
            return BrowserToolbarItem(rawValue: raw).map(ToolbarEntry.init)
        }
        guard !entries.isEmpty else { self = .standard; return }
        if !entries.contains(where: { $0.items.contains(.allActions) }) { entries.append(ToolbarEntry(.allActions)) }
        self.init(entries: entries)
    }

    init(items: [BrowserToolbarItem]) { self.init(entries: items.map(ToolbarEntry.init)) }
    init(entries: [ToolbarEntry]) {
        var seen = Set<BrowserToolbarItem>()
        var ids = Set<String>()
        self.entries = entries.flatMap { entry -> [ToolbarEntry] in
            let items = entry.items.filter { seen.insert($0).inserted }
            var result: [ToolbarEntry] = []
            var buttons: [BrowserToolbarItem] = []
            func flushButtons() {
                guard !buttons.isEmpty else { return }
                if buttons.count == 1 { result.append(ToolbarEntry(buttons[0])) }
                else {
                    let id = entry.id.hasPrefix("group.") && ids.insert(entry.id).inserted ? entry.id : "group.\(UUID().uuidString)"
                    result.append(ToolbarEntry(id: id, items: buttons))
                }
                buttons = []
            }
            // Split older groups around Profile/Address without changing the flattened order.
            for item in items {
                if item.canGroup { buttons.append(item) }
                else { flushButtons(); result.append(ToolbarEntry(item)) }
            }
            flushButtons()
            return result
        }
        if !seen.contains(.profile) { self.entries.insert(ToolbarEntry(.profile), at: 0) }
        if !seen.contains(.address) { self.entries.append(ToolbarEntry(.address)) }
    }

    func entry(containing item: BrowserToolbarItem) -> ToolbarEntry? { entries.first { $0.items.contains(item) } }
    func canGroup(_ id: String) -> Bool {
        guard let source = location(id) else { return false }
        if let child = source.child { return entries[source.root].items[child].canGroup }
        return entries[source.root].items.allSatisfy(\.canGroup)
    }
    func siblings(of id: String) -> [String] {
        if entries.contains(where: { $0.id == id }) { return entries.map(\.id) }
        return entries.first(where: { $0.items.contains { $0.rawValue == id } })?.items.map(\.rawValue) ?? []
    }
    mutating func add(_ item: BrowserToolbarItem) {
        guard !items.contains(item) else { return }
        entries.append(ToolbarEntry(item))
    }
    mutating func remove(_ item: BrowserToolbarItem) {
        guard !item.isRequired else { return }
        for index in entries.indices { entries[index].items.removeAll { $0 == item } }
        normalize()
    }
    mutating func move(_ id: String, by offset: Int) {
        let siblings = siblings(of: id)
        guard let index = siblings.firstIndex(of: id), siblings.indices.contains(index + offset) else { return }
        let parent = entries.first(where: { $0.isGroup && $0.items.contains { $0.rawValue == id } })?.id
        _ = move(id, toGroup: parent, at: index + offset + (offset > 0 ? 1 : 0))
    }

    /// Move over a visible row, just like tabs: downwards goes after it, upwards before it.
    /// Group headers reorder whole entries; child rows accept groupable buttons.
    @discardableResult
    mutating func move(_ id: String, over targetID: String) -> Bool {
        guard id != targetID, let source = location(id), let target = location(targetID) else { return false }
        let sourceIsGroup = source.child == nil && entries[source.root].isGroup
        // Whole groups and required controls use group headers, never individual child targets.
        guard target.child == nil || (!sourceIsGroup && canGroup(id)) else { return false }
        let intoGroup = target.child != nil
        let parent = intoGroup ? entries[target.root].id : nil
        // A group cannot be moved onto its own children.
        guard parent != id, !(sourceIsGroup && source.root == target.root) else { return false }
        let oldParent = source.child == nil ? nil : entries[source.root].id
        let targetIndex = target.child ?? target.root
        let sourceIndex = source.child ?? source.root
        let destination = targetIndex + (oldParent == parent && sourceIndex < targetIndex ? 1 : 0)
        let old = self
        _ = move(id, toGroup: parent, at: destination)
        return self != old
    }

    /// Destination indices refer to the list before removing the source.
    @discardableResult
    mutating func move(_ id: String, toGroup groupID: String?, at proposedIndex: Int) -> Bool {
        guard let source = location(id), groupID != id else { return false }
        if let groupID {
            guard canGroup(id), entries.contains(where: { $0.id == groupID && $0.isGroup }) else { return false }
        }
        let oldParent = source.child == nil ? nil : entries[source.root].id
        var index = proposedIndex
        if oldParent == groupID, (source.child ?? source.root) < index { index -= 1 }
        let moved = take(source)
        if let groupID, let target = entries.firstIndex(where: { $0.id == groupID }) {
            entries[target].items.insert(contentsOf: moved.items, at: max(0, min(index, entries[target].items.count)))
        } else {
            entries.insert(moved, at: max(0, min(index, entries.count)))
        }
        normalize()
        return true
    }

    mutating func group(_ id: String, with targetID: String) {
        guard id != targetID, canGroup(id), canGroup(targetID), let source = location(id),
              let target = entries.first(where: { $0.id == targetID }),
              !target.items.contains(where: { $0.rawValue == id }) else { return }
        let moved = take(source)
        guard let index = entries.firstIndex(where: { $0.id == targetID }) else { return }
        entries[index] = ToolbarEntry(id: target.isGroup ? target.id : "group.\(UUID().uuidString)",
                                      items: target.items + moved.items)
        normalize()
    }
    mutating func ungroup(_ id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id && $0.isGroup }) else { return }
        entries.replaceSubrange(index...index, with: entries[index].items.map(ToolbarEntry.init))
    }
    mutating func separate(_ item: BrowserToolbarItem) {
        guard let index = entries.firstIndex(where: { $0.isGroup && $0.items.contains(item) }) else { return }
        entries[index].items.removeAll { $0 == item }
        entries.insert(ToolbarEntry(item), at: index + 1)
        normalize()
    }
    private func location(_ id: String) -> (root: Int, child: Int?)? {
        for index in entries.indices {
            if entries[index].id == id { return (index, nil) }
            if let child = entries[index].items.firstIndex(where: { $0.rawValue == id }) { return (index, child) }
        }
        return nil
    }
    private mutating func take(_ location: (root: Int, child: Int?)) -> ToolbarEntry {
        if let child = location.child { return ToolbarEntry(entries[location.root].items.remove(at: child)) }
        return entries.remove(at: location.root)
    }
    private mutating func normalize() { self = Self(entries: entries) }

    /// Overflow changes presentation only, leaving saved groups and ordering intact.
    func presentation(width: CGFloat, hasDownloads: Bool = false, isPrivate: Bool = false) -> ToolbarPresentation {
        let compactProfile = width < 540
        var visible = entries
        if hasDownloads && !items.contains(.downloads) { visible.append(ToolbarEntry(.downloads)) }
        var hidden = Set<BrowserToolbarItem>()
        func requiredWidth() -> CGFloat {
            visible.reduce(CGFloat(0)) { result, entry in
                result + entry.items.reduce(CGFloat(4)) { result, item in
                    result + (item == .address ? 160 : item == .profile ? (isPrivate ? 94 : compactProfile ? 34 : 132) : 30)
                }
            } + CGFloat(max(0, visible.count - 1)) * 6
                + (!hidden.isEmpty && !visible.contains(where: { $0.items.contains(.allActions) }) ? 40 : 0)
        }
        while requiredWidth() > width,
              let item = visible.flatMap(\.items).last(where: \.canOverflow) {
            hidden.insert(item)
            visible = visible.compactMap { entry in
                let remaining = entry.items.filter { $0 != item }
                return remaining.isEmpty ? nil : ToolbarEntry(id: entry.id, items: remaining)
            }
        }
        let all = entries.flatMap(\.items) + (items.contains(.downloads) ? [] : [.downloads])
        return ToolbarPresentation(visible: visible, overflow: all.filter { hidden.contains($0) }, compactProfile: compactProfile)
    }
}

struct ToolbarPresentation {
    let visible: [ToolbarEntry]
    let overflow: [BrowserToolbarItem]
    let compactProfile: Bool
}
