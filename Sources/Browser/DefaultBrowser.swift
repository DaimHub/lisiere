import AppKit
import Observation
import SwiftUI

/// Keeps Launch Services writes behind a user action and makes the flow testable without changing macOS.
@MainActor
protocol DefaultBrowserSystem {
    func handlerIdentifier(for scheme: String) -> String?
    func setDefault(for scheme: String) async throws
    func openSettings() -> Bool
}

@MainActor
struct WorkspaceDefaultBrowserSystem: DefaultBrowserSystem {
    func handlerIdentifier(for scheme: String) -> String? {
        guard let probe = URL(string: "\(scheme)://example.com"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return nil }
        return Bundle(url: handler)?.bundleIdentifier
    }

    func setDefault(for scheme: String) async throws {
        try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
    }

    func openSettings() -> Bool {
        // Pane links can change between macOS releases; the root remains a useful fallback.
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
            || NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:")!)
    }
}

/// Whether macOS opens web links from other apps in this app, and asks it to.
@MainActor
@Observable
final class DefaultBrowser {
    enum Status {
        case unknown, notDefault, partial, defaultBrowser
    }

    enum Notice {
        case cancelled, notCompleted, failed, settingsUnavailable
    }

    private(set) var status = Status.unknown
    private(set) var isRequesting = false
    private(set) var notice: Notice?
    var isDefault: Bool { status == .defaultBrowser }

    @ObservationIgnored private let system: any DefaultBrowserSystem
    @ObservationIgnored private let bundleIdentifier: String?
    @ObservationIgnored private var handlers: [String: String] = [:]
    private static let schemes = ["http", "https"]

    init(system: any DefaultBrowserSystem = WorkspaceDefaultBrowserSystem(),
         bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        self.system = system
        self.bundleIdentifier = bundleIdentifier
    }

    func refresh() {
        handlers = [:]
        for scheme in Self.schemes {
            handlers[scheme] = system.handlerIdentifier(for: scheme)
        }
        let previous = status
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            let matches = handlers.values.filter { $0 == bundleIdentifier }.count
            switch matches {
            case 2: status = .defaultBrowser
            case 1: status = .partial
            default: status = handlers.count == Self.schemes.count ? .notDefault : .unknown
            }
        } else {
            status = .unknown
        }
        if status != previous || isDefault { notice = nil }
    }

    /// Only called after an explicit click. macOS may ask for consent before completing each request.
    func makeDefault() async {
        guard !isRequesting else { return }
        refresh()
        guard !isDefault else { return }
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
            notice = .failed
            return
        }
        notice = nil
        isRequesting = true
        defer { isRequesting = false }
        do {
            for scheme in Self.schemes {
                try Task.checkCancellation()
                // macOS may change both schemes together. Recheck before requesting another confirmation.
                refresh()
                guard handlers[scheme] != bundleIdentifier else { continue }
                try await system.setDefault(for: scheme)
                refresh()
                // A completed call alone is not proof of a changed association. Do not prompt again if
                // the first request was declined without an error, or its result is not yet visible.
                guard handlers[scheme] == bundleIdentifier else {
                    notice = .notCompleted
                    return
                }
            }
            refresh()
            if !isDefault { notice = .notCompleted }
        } catch {
            refresh()
            if !isDefault { notice = Self.isCancellation(error) ? .cancelled : .failed }
        }
        // Local HTML/XHTML file associations are a separate preference; leave them alone.
    }

    func openSystemSettings() {
        guard !isRequesting else { return }
        notice = system.openSettings() ? nil : .settingsUnavailable
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let error = error as NSError
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        let errors: [NSError?] = [error, underlying]
        for case let candidate? in errors {
            if candidate.domain == NSCocoaErrorDomain && candidate.code == NSUserCancelledError { return true }
            if candidate.domain == NSOSStatusErrorDomain && candidate.code == -128 { return true } // userCanceledErr
        }
        return false
    }
}

/// Opens the links and files other apps hand to the browser, such as a link clicked in Mail once it's the default
/// browser: in new tabs of the frontmost normal window, or in a new window when only private windows are open.
@MainActor
final class ExternalURLRouter {
    static let shared = ExternalURLRouter()

    private var browsers: [WeakBrowser] = []
    /// Links waiting for the window that was asked to open for them.
    private var pendingURLs: [URL] = []
    private var isOpeningWindow = false
    private var openWindow: OpenWindowAction?

    private struct WeakBrowser {
        weak var browser: BrowserModel?
    }

    /// Web pages and local files open; other schemes, like `javascript:`, are ignored.
    static func canOpen(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "http", "https": url.host()?.isEmpty == false
        case "file": url.isFileURL
        default: false
        }
    }

    /// The first normal window of those open, front to back. A private window never takes links from other apps,
    /// since the user didn't choose to open them privately.
    static func destination(among browsers: [BrowserModel]) -> BrowserModel? {
        browsers.first { !$0.isPrivate }
    }

    /// A window joins when it appears, and takes the links that were waiting for a window to open.
    func register(_ browser: BrowserModel, openWindow: OpenWindowAction? = nil) {
        if let openWindow { self.openWindow = openWindow }
        browsers.removeAll { $0.browser == nil || $0.browser === browser }
        browsers.append(WeakBrowser(browser: browser))
        guard !browser.isPrivate else { return }
        isOpeningWindow = false
        let urls = pendingURLs
        pendingURLs = []
        browser.openInNewTabs(urls)
    }

    func open(_ urls: [URL]) {
        let urls = urls.filter(Self.canOpen)
        guard !urls.isEmpty else { return }
        let windows = NSApp.orderedWindows
        let frontToBack = { (browser: BrowserModel) in
            windows.firstIndex { $0 === browser.window } ?? .max
        }
        let open = browsers.compactMap(\.browser).sorted { frontToBack($0) < frontToBack($1) }
        if let browser = Self.destination(among: open) {
            browser.openInNewTabs(urls)
            if let window = browser.window {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate()
            return
        }
        // At launch the first window appears on its own, and takes the links when it registers.
        pendingURLs += urls
        if let openWindow, !isOpeningWindow {
            isOpeningWindow = true
            openWindow(id: BrowserApp.windowID)
        }
    }
}

final class BrowserAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Passkeys.shared.requestAuthorizationIfNeeded()
    }

    /// Links and HTML files opened from other apps and the Finder.
    func application(_ application: NSApplication, open urls: [URL]) {
        ExternalURLRouter.shared.open(urls)
    }
}
