import AppKit
import Hugeicons
import SwiftUI

/// The app's icon vocabulary, backed by Hugeicons Free Stroke Rounded.
/// Keep assets here so SwiftUI controls and AppKit menus share the same artwork.
enum BrowserIcon: CaseIterable {
    case back
    case forward
    case reload
    case search
    case add
    case subtract
    case home
    case privateWindow
    case history
    case downloads
    case book
    case settings
    case more
    case profile
    case profiles
    case profileUnavailable
    case close
    case chevronDown
    case chevronUp
    case download
    case file
    case checkmark
    case checkmarkCircle
    case circle
    case remove
    case view
    case viewOff
    case copy
    case secure
    case key
    case shield
    case shieldOff
    case warning
    case wifiOff
    case secureError
    case appearance
    case privacy
    case sliders
    case group
    case link
    case ungroup
    case drag
    case briefcase
    case globe
    case code
    case leaf
    case star
    case heart
    case game
    case graduation
    case flask
    case bookmark
    case bookmarkSelected
    case window
    case reopen
    case printPage
    case zoomIn
    case zoomOut
    case actualSize
    case horizontalTabs
    case verticalTabs
    case open
    case rename
    case trash
    case folder
    case spelling
    case selection
    case speak
    case stop

    var asset: HugeiconsAsset {
        switch self {
        case .back: Hugeicons.arrowLeft01
        case .forward: Hugeicons.arrowRight01
        case .reload: Hugeicons.refresh
        case .search: Hugeicons.search01
        case .add: Hugeicons.add01
        case .subtract: Hugeicons.minusSign
        case .home: Hugeicons.home01
        case .privateWindow: Hugeicons.incognito
        case .history: Hugeicons.clock01
        case .downloads: Hugeicons.circleArrowDown02
        case .book: Hugeicons.bookOpen01
        case .settings: Hugeicons.settings01
        case .more: Hugeicons.moreHorizontal
        case .profile: Hugeicons.userCircle
        case .profiles: Hugeicons.userGroup
        case .profileUnavailable: Hugeicons.userWarning01
        case .close: Hugeicons.cancel01
        case .chevronDown: Hugeicons.arrowDown01
        case .chevronUp: Hugeicons.arrowUp01
        case .download: Hugeicons.arrowDown02
        case .file: Hugeicons.file01
        case .checkmark: Hugeicons.tick02
        case .checkmarkCircle: Hugeicons.checkmarkCircle02
        case .circle: Hugeicons.circle
        case .remove: Hugeicons.minusSignCircle
        case .view: Hugeicons.view
        case .viewOff: Hugeicons.viewOffSlash
        case .copy: Hugeicons.copy01
        case .secure: Hugeicons.lock
        case .key: Hugeicons.key01
        case .shield: Hugeicons.securityCheck
        case .shieldOff: Hugeicons.shieldBan
        case .warning: Hugeicons.alert02
        case .wifiOff: Hugeicons.wifiOff02
        case .secureError: Hugeicons.securityWarning
        case .appearance: Hugeicons.paintBoard
        case .privacy: Hugeicons.securityLock
        case .sliders: Hugeicons.slidersHorizontal
        case .group: Hugeicons.layoutThreeColumn
        case .link: Hugeicons.link01
        case .ungroup: Hugeicons.layoutThreeColumn
        case .drag: Hugeicons.gripVertical
        case .briefcase: Hugeicons.briefcase01
        case .globe: Hugeicons.internet
        case .code: Hugeicons.code
        case .leaf: Hugeicons.leaf01
        case .star: Hugeicons.star
        case .heart: Hugeicons.heart
        case .game: Hugeicons.gameController03
        case .graduation: Hugeicons.mortarboard01
        case .flask: Hugeicons.testTube01
        case .bookmark: Hugeicons.bookmark02
        case .bookmarkSelected: Hugeicons.bookmarkCheck02
        case .window: Hugeicons.browser
        case .reopen: Hugeicons.arrowTurnBackward
        case .printPage: Hugeicons.printer
        case .zoomIn: Hugeicons.zoomInArea
        case .zoomOut: Hugeicons.zoomOutArea
        case .actualSize: Hugeicons.arrowExpand
        case .horizontalTabs: Hugeicons.layoutTop
        case .verticalTabs: Hugeicons.layoutLeft
        case .open: Hugeicons.arrowUpRight01
        case .rename: Hugeicons.edit02
        case .trash: Hugeicons.delete02
        case .folder: Hugeicons.folderSearch
        case .spelling: Hugeicons.textCheck
        case .selection: Hugeicons.textSelection
        case .speak: Hugeicons.volumeHigh
        case .stop: Hugeicons.stop
        }
    }

    /// macOS expands Settings tab images to a 32-point slot, ignoring their requested size.
    /// Keep 24-point artwork centered inside that slot instead of stretching it to fill.
    @MainActor
    func settingsTabImage() -> NSImage {
        let artwork = nsImage(size: 24)
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { bounds in
            artwork.draw(in: bounds.insetBy(dx: 4, dy: 4))
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Give menu artwork a stable native identity without changing package assets.
    @MainActor
    func menuImage() -> NSImage {
        let name = NSImage.Name("Lisiere.Hugeicons.\(self)")
        if let image = NSImage(named: name) { return image }
        let image = nsImage()
        image.setName(name)
        return image
    }

    /// Copy before resizing: the package caches its original 24-point template image.
    @MainActor
    func nsImage(size: CGFloat = 14, accessibilityDescription: String? = nil) -> NSImage {
        // The pinned Swift package's home01 still has the old inner curve.
        // Use the current official Home01Icon artwork for every Home surface.
        let original = self == .home ? NSImage(named: "BrowserHome01") : asset.nsImage()
        guard let image = original?.copy() as? NSImage else {
            preconditionFailure("Missing Hugeicons resource: \(asset.resourceName)")
        }
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}

extension Image {
    @MainActor
    init(browserIcon: BrowserIcon, size: CGFloat = 14) {
        self = Image(nsImage: browserIcon.nsImage(size: size)).renderingMode(.template)
    }
}

extension Label where Title == Text, Icon == Image {
    @MainActor
    init(_ title: String, browserIcon: BrowserIcon, size: CGFloat = 14) {
        self.init { Text(title) } icon: { Image(browserIcon: browserIcon, size: size) }
    }

    @MainActor
    init(_ title: String, settingsIcon: BrowserIcon) {
        self.init { Text(title) } icon: {
            Image(nsImage: settingsIcon.settingsTabImage()).renderingMode(.template)
        }
    }
}

typealias BrowserMenuLabel = Label<Text, Image>

extension Label where Title == Text, Icon == Image {
    @MainActor
    init(title: String, icon: BrowserIcon) {
        self.init { Text(title) } icon: {
            Image(nsImage: icon.menuImage())
        }
    }
}

extension Button where Label == BrowserMenuLabel {
    @MainActor
    init(_ title: String, browserIcon: BrowserIcon, role: ButtonRole? = nil,
         action: @escaping () -> Void) {
        self.init(role: role, action: action) {
            BrowserMenuLabel(title: title, icon: browserIcon)
        }
    }
}

extension Menu where Label == BrowserMenuLabel {
    @MainActor
    init(_ title: String, browserIcon: BrowserIcon, @ViewBuilder content: () -> Content) {
        self.init(content: content) { BrowserMenuLabel(title: title, icon: browserIcon) }
    }
}

/// macOS 27 hides menu images by default. Keep native image slots visible instead of
/// forcing a SwiftUI title-and-icon layout, which rasterizes the label before selection.
@MainActor
final class BrowserMenuImages: NSObject {
    static let shared = BrowserMenuImages()
    private var isUpdating = false
    private var isStarted = false
    func start() {
        guard !isStarted else { return }
        isStarted = true
        if #available(macOS 27.0, *) {
            for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification, NSMenu.didBeginTrackingNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(update(_:)), name: name, object: nil)
            }
        }
    }
    @objc private func update(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        guard !isUpdating else { return }
        isUpdating = true
        showImages(in: menu)
        isUpdating = false
    }
    static func keepImageVisible(_ item: NSMenuItem) {
        if #available(macOS 27.0, *) {
            // Public macOS 27 property, accessed through KVC so Xcode 26 CI can still compile.
            let key = "preferredImageVisibility"
            let visible = 1 // NSMenuItem.ImageVisibility.visible
            if item.value(forKey: key) as? Int != visible { item.setValue(visible, forKey: key) }
        }
    }
    func showImages(in menu: NSMenu) {
        if #available(macOS 27.0, *) {
            for item in menu.items {
                if let image = item.image, image.name()?.hasPrefix("Lisiere.Hugeicons.") == true {
                    Self.keepImageVisible(item)
                    if !image.isTemplate, let copy = image.copy() as? NSImage {
                        copy.isTemplate = true
                        item.image = copy
                    }
                }
                if let submenu = item.submenu { showImages(in: submenu) }
            }
        }
    }
}
