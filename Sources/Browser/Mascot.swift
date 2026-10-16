import AppKit

/// A shared choice for the start page and the running app's Dock icon.
enum Mascot: String, CaseIterable, Identifiable {
    case veilleur
    case eclaireur
    case lutin
    case lapin
    case ourson
    case nuage
    case flamme
    case goutte
    case pollen

    static let storageKey = "mascot"
    static let defaultChoice = Mascot.lutin

    var id: Self { self }
    func imageName(for palette: MascotPalette) -> String { "Mascot-\(rawValue)\(palette.assetSuffix)" }
    func iconName(for palette: MascotPalette) -> String { "Dock-\(rawValue)\(palette.assetSuffix)" }

    var title: String {
        switch self {
        case .veilleur: "Veilleur"
        case .eclaireur: "Éclaireur"
        case .lutin: "Lutin"
        case .lapin: "Lapin"
        case .ourson: "Ourson"
        case .nuage: "Nuage"
        case .flamme: "Flamme"
        case .goutte: "Goutte"
        case .pollen: "Pollen"
        }
    }

    static func current(in defaults: UserDefaults = .standard) -> Mascot {
        defaults.string(forKey: storageKey).flatMap(Mascot.init(rawValue:)) ?? defaultChoice
    }

    @MainActor
    func applyDockIcon(palette: MascotPalette = .current()) {
        // nil restores the compiled Icon Composer icon, including system appearance variants.
        // AppKit only changes the running Dock tile; Finder keeps the signed bundle's icon.
        guard self != Self.defaultChoice || palette != .black else {
            NSApp.applicationIconImage = nil
            return
        }
        guard let image = NSImage(named: iconName(for: palette)) else { return }
        // Composer's PNG export fills its canvas. The compiled macOS icon has a 100 px
        // inset at 1024 px; use the same footprint for alternate Dock tiles.
        let dockImage = NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { bounds in
            image.draw(in: bounds.insetBy(dx: 100, dy: 100))
            return true
        }
        NSApp.applicationIconImage = dockImage
    }
}

/// An explicit color choice, independent of the Mac's light/dark appearance.
enum MascotPalette: String, CaseIterable, Identifiable {
    case black
    case white

    static let storageKey = "mascotPalette"
    static let defaultChoice = MascotPalette.black

    var id: Self { self }
    var assetSuffix: String { self == .black ? "" : "-white" }
    var title: String { self == .black ? "Black on light" : "White on black" }

    static func current(in defaults: UserDefaults = .standard) -> MascotPalette {
        defaults.string(forKey: storageKey).flatMap(MascotPalette.init(rawValue:)) ?? defaultChoice
    }
}
