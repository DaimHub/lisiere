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

    var asset: HugeiconsAsset {
        switch self {
        case .back: Hugeicons.arrowLeft01
        case .forward: Hugeicons.arrowRight01
        case .reload: Hugeicons.reload
        case .search: Hugeicons.search01
        case .add: Hugeicons.add01
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
        case .appearance: Hugeicons.browser
        case .privacy: Hugeicons.hand
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
        }
    }

    /// Copy before resizing: the package caches its original 24-point template image.
    @MainActor
    func nsImage(size: CGFloat = 14, accessibilityDescription: String? = nil) -> NSImage {
        guard let image = asset.nsImage()?.copy() as? NSImage else {
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
}
