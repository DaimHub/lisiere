import AppKit
import Observation
import SwiftUI
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

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
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
            defaults?.set(selection.rawValue, forKey: BrowserAppearance.storageKey)
            if appliesToApplication { applyAppearance(selection.appearance) }
            refreshWebViews()
        }
    }

    var pageSelection: WebPageAppearance {
        didSet {
            guard pageSelection != oldValue else { return }
            defaults?.set(pageSelection.rawValue, forKey: WebPageAppearance.storageKey)
            if pageSelection != .followApp {
                defaults?.set(pageSelection.rawValue, forKey: WebPageAppearance.separateStorageKey)
            }
            refreshWebViews()
        }
    }

    /// Turning this off resumes inheritance; turning it back on restores the user's separate choice.
    var usesSeparatePageTheme: Bool {
        get { pageSelection != .followApp }
        set {
            guard newValue != usesSeparatePageTheme else { return }
            if newValue {
                let saved = defaults?.string(forKey: WebPageAppearance.separateStorageKey)
                    .flatMap(WebPageAppearance.init)
                let appAppearance = selection.appearance ?? NSApp.effectiveAppearance
                let current: WebPageAppearance = appAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    ? .dark : .light
                pageSelection = saved.flatMap { $0 == .followApp ? nil : $0 } ?? current
            } else {
                pageSelection = .followApp
            }
        }
    }

    // Background tabs must update too, without retaining closed or suspended web views.
    @ObservationIgnored private let webViews = NSHashTable<WKWebView>.weakObjects()
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let appliesToApplication: Bool
    @ObservationIgnored private let applyAppearance: (NSAppearance?) -> Void

    init(defaults: UserDefaults? = .standard, appliesToApplication: Bool = true,
         applyAppearance: @escaping (NSAppearance?) -> Void = { NSApp.appearance = $0 }) {
        self.defaults = defaults
        self.appliesToApplication = appliesToApplication
        self.applyAppearance = applyAppearance
        selection = defaults?.string(forKey: BrowserAppearance.storageKey).flatMap(BrowserAppearance.init) ?? .system
        pageSelection = defaults?.string(forKey: WebPageAppearance.storageKey).flatMap(WebPageAppearance.init) ?? .followApp
        // Set this before the first window appears. nil returns ownership to macOS, including live system changes.
        if appliesToApplication { applyAppearance(selection.appearance) }
    }

    /// Called for every new web view, including pop-ups and recreated suspended tabs, before it loads a page.
    func attach(_ webView: WKWebView) {
        webViews.add(webView)
        applyPageAppearance(to: webView)
    }

    private func refreshWebViews() {
        for webView in webViews.allObjects {
            applyPageAppearance(to: webView)
        }
    }

    private func applyPageAppearance(to webView: WKWebView) {
        // Private pages always advertise dark mode, regardless of a regular profile's preferences.
        if !webView.configuration.websiteDataStore.isPersistent {
            webView.appearance = NSAppearance(named: .darkAqua)
        } else if pageSelection == .followApp, !appliesToApplication {
            webView.appearance = selection.appearance
        } else {
            webView.appearance = pageSelection.appearance
        }
    }
}
