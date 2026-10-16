import AppKit
import Observation
import WebKit

/// The appearance of the browser interface, including every native window and panel.
enum BrowserAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "browserAppearance"
    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Websites may follow the app or request a different appearance. They still own their styles.
enum WebPageAppearance: String, CaseIterable, Identifiable {
    case followApp
    case light
    case dark

    static let storageKey = "webPageAppearance"
    static let separateStorageKey = "separateWebPageAppearance"
    static let separateChoices: [Self] = [.light, .dark]
    var id: Self { self }

    var title: String {
        switch self {
        case .followApp: "Follow Lisière"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .followApp: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
@Observable
final class AppearanceStore {
    static let shared = AppearanceStore()

    var selection: BrowserAppearance {
        didSet {
            guard selection != oldValue else { return }
            defaults.set(selection.rawValue, forKey: BrowserAppearance.storageKey)
            applyAppearance(selection.appearance)
        }
    }

    var pageSelection: WebPageAppearance {
        didSet {
            guard pageSelection != oldValue else { return }
            defaults.set(pageSelection.rawValue, forKey: WebPageAppearance.storageKey)
            if pageSelection != .followApp {
                defaults.set(pageSelection.rawValue, forKey: WebPageAppearance.separateStorageKey)
            }
            for webView in webViews.allObjects {
                webView.appearance = pageSelection.appearance
            }
        }
    }

    /// Turning this off resumes inheritance; turning it back on restores the user's separate choice.
    var usesSeparatePageTheme: Bool {
        get { pageSelection != .followApp }
        set {
            guard newValue != usesSeparatePageTheme else { return }
            if newValue {
                let saved = defaults.string(forKey: WebPageAppearance.separateStorageKey)
                    .flatMap(WebPageAppearance.init)
                let current: WebPageAppearance = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    ? .dark : .light
                pageSelection = saved.flatMap { $0 == .followApp ? nil : $0 } ?? current
            } else {
                pageSelection = .followApp
            }
        }
    }

    // Background tabs must update too, without retaining closed or suspended web views.
    @ObservationIgnored private let webViews = NSHashTable<WKWebView>.weakObjects()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let applyAppearance: (NSAppearance?) -> Void

    init(defaults: UserDefaults = .standard,
         applyAppearance: @escaping (NSAppearance?) -> Void = { NSApp.appearance = $0 }) {
        self.defaults = defaults
        self.applyAppearance = applyAppearance
        selection = defaults.string(forKey: BrowserAppearance.storageKey).flatMap(BrowserAppearance.init) ?? .system
        pageSelection = defaults.string(forKey: WebPageAppearance.storageKey).flatMap(WebPageAppearance.init) ?? .followApp
        // Set this before the first window appears. nil returns ownership to macOS, including live system changes.
        applyAppearance(selection.appearance)
    }

    /// Called for every new web view, including pop-ups and recreated suspended tabs, before it loads a page.
    func attach(_ webView: WKWebView) {
        webViews.add(webView)
        webView.appearance = pageSelection.appearance
    }
}
