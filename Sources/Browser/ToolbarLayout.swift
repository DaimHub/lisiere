import Foundation

/// Stable identifiers stored with the profile. Navigation stays together as one movable group.
enum BrowserToolbarItem: String, CaseIterable, Identifiable {
    case profile, navigation, address, newTab, home, privateWindow, history, downloads, bookmarks, settings

    var id: Self { self }
    var isRequired: Bool { self == .profile || self == .address }
    var canOverflow: Bool { ![.profile, .navigation, .address, .newTab].contains(self) }

    var title: String {
        switch self {
        case .profile: "Profile"
        case .navigation: "Back, Forward & Reload"
        case .address: "Address & Search"
        case .newTab: "New Tab"
        case .home: "Home"
        case .privateWindow: "New Private Window"
        case .history: "History"
        case .downloads: "Downloads"
        case .bookmarks: "Bookmarks Bar"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .profile: "person.crop.circle"
        case .navigation: "arrow.left.arrow.right"
        case .address: "magnifyingglass"
        case .newTab: "plus"
        case .home: "house"
        case .privateWindow: "eyeglasses"
        case .history: "clock.arrow.circlepath"
        case .downloads: "arrow.down.circle"
        case .bookmarks: "book"
        case .settings: "gearshape"
        }
    }
}

struct BrowserToolbarLayout: Equatable {
    static let storageKey = "navigationToolbarItems"
    static let defaultItems: [BrowserToolbarItem] = [.profile, .navigation, .address, .newTab]
    static let standard = Self(items: defaultItems)
    private(set) var items: [BrowserToolbarItem]
    var storedValue: [String] { items.map(\.rawValue) }
    var availableItems: [BrowserToolbarItem] { BrowserToolbarItem.allCases.filter { !items.contains($0) } }

    init(storedValue: [String]?) {
        let known = storedValue?.compactMap(BrowserToolbarItem.init(rawValue:)) ?? []
        self.init(items: known.isEmpty ? Self.defaultItems : known)
    }

    init(items: [BrowserToolbarItem]) {
        var unique: [BrowserToolbarItem] = []
        for item in items where !unique.contains(item) { unique.append(item) }
        if !unique.contains(.profile) { unique.insert(.profile, at: 0) }
        if !unique.contains(.address) { unique.append(.address) }
        self.items = unique
    }

    mutating func add(_ item: BrowserToolbarItem) {
        guard !items.contains(item) else { return }
        items.append(item)
    }

    mutating func remove(_ item: BrowserToolbarItem) {
        guard !item.isRequired else { return }
        items.removeAll { $0 == item }
    }

    mutating func move(_ item: BrowserToolbarItem, by offset: Int) {
        guard let index = items.firstIndex(of: item), items.indices.contains(index + offset) else { return }
        items.swapAt(index, index + offset)
    }

    /// Keep a usable address field in narrow windows; additional actions remain available in More.
    func presentation(width: CGFloat, hasDownloads: Bool = false) -> ToolbarPresentation {
        let compactProfile = width < 540
        var visible = items
        if hasDownloads && !visible.contains(.downloads) { visible.append(.downloads) }
        var overflow: [BrowserToolbarItem] = []
        func requiredWidth() -> CGFloat {
            visible.reduce(CGFloat(0)) { result, item in
                result + (item == .address ? 160 : item == .profile ? (compactProfile ? 34 : 132)
                          : item == .navigation ? 94 : 34)
            } + CGFloat(max(0, visible.count - 1)) * 6 + (overflow.isEmpty ? 0 : 40)
        }
        while requiredWidth() > width, let item = visible.last(where: \.canOverflow) {
            visible.removeAll { $0 == item }
            overflow.insert(item, at: 0)
        }
        return ToolbarPresentation(visible: visible, overflow: overflow, compactProfile: compactProfile)
    }
}

struct ToolbarPresentation {
    let visible: [BrowserToolbarItem]
    let overflow: [BrowserToolbarItem]
    let compactProfile: Bool
}
