import AppKit
import Observation
import SwiftUI
import WebKit

@MainActor
@Observable
final class BrowserTab: Identifiable {
    let id = UUID()
    /// The page's web view, or `nil` while the tab is suspended to free its memory.
    private(set) var webView: WKWebView?
    /// Hosts the web view, and the Web Inspector when it's docked, so both move together between windows and tabs.
    let contentView = NSView()
    var isNewTab = true
    /// The tab whose page opened this one, so its links and pop-ups open next to each other.
    @ObservationIgnored var openerID: UUID?
    @ObservationIgnored weak var browser: BrowserModel?
    var favicon: Image?
    var thumbnail: Image?

    private(set) var url: URL?
    private(set) var pageTitle = ""
    private(set) var isLoading = false
    private(set) var estimatedProgress = 0.0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var hasOnlySecureContent = false
    private(set) var backList: [WKBackForwardListItem] = []
    private(set) var forwardList: [WKBackForwardListItem] = []

    @ObservationIgnored private let pageDelegate = PageDelegate()
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var thumbnailTask: Task<Void, Never>?
    @ObservationIgnored private var faviconTask: Task<Void, Never>?
    /// The history and scroll position a suspended tab brings back when it's restored.
    @ObservationIgnored private var suspendedState: Any?
    private var faviconHost: String?

    /// Pass the configuration WebKit provides when a page opens a window, so the new page keeps its opener.
    init(configuration: WKWebViewConfiguration = BrowserTab.makeConfiguration()) {
        pageDelegate.tab = self
        install(WKWebView(frame: .zero, configuration: configuration))
    }

    /// A suspended tab for a page's saved history, such as a duplicated or reopened tab, which loads when it's selected.
    init(url: URL?, title: String, interactionState: Any?) {
        isNewTab = false
        self.url = url
        pageTitle = title
        suspendedState = interactionState
        pageDelegate.tab = self
    }

    var isSuspended: Bool {
        webView == nil
    }

    /// The tab's history and scroll position, whether or not it's suspended.
    var interactionState: Any? {
        webView?.interactionState ?? suspendedState
    }

    /// Restoring keeps the suspended page's state until the new web view reports its own, which it only does
    /// once the page starts loading, so the tab's title and address don't flash blank.
    private func install(_ webView: WKWebView, isRestoring: Bool = false) {
        webView.isInspectable = true
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.allowsLinkPreview = true
        webView.frame = contentView.bounds
        webView.autoresizingMask = [.width, .height]
        contentView.addSubview(webView)
        webView.navigationDelegate = pageDelegate
        webView.uiDelegate = pageDelegate
        self.webView = webView

        let options: NSKeyValueObservingOptions = isRestoring ? [] : .initial
        observe(webView, \.url, options) { tab, webView in
            tab.url = webView.url
            // Same-document navigations don't load, but can still change the icon.
            if !webView.isLoading { tab.updateFavicon() }
        }
        observe(webView, \.title, options) { $0.pageTitle = $1.title ?? "" }
        observe(webView, \.isLoading, options) { tab, webView in
            let didFinish = tab.isLoading && !webView.isLoading
            tab.isLoading = webView.isLoading
            if didFinish {
                tab.scheduleThumbnail()
                tab.updateFavicon()
            }
        }
        observe(webView, \.estimatedProgress, options) { $0.estimatedProgress = $1.estimatedProgress }
        observe(webView, \.canGoBack, options) { $0.canGoBack = $1.canGoBack }
        observe(webView, \.canGoForward, options) { $0.canGoForward = $1.canGoForward }
        observe(webView, \.hasOnlySecureContent, options) { $0.hasOnlySecureContent = $1.hasOnlySecureContent }
    }

    /// Releases the web view, and with it the page's memory, keeping what the tab strip shows and the state to restore.
    func suspend() {
        guard let webView, !isNewTab else { return }
        suspendedState = webView.interactionState
        observations.forEach { $0.invalidate() }
        observations = []
        thumbnailTask?.cancel()
        faviconTask?.cancel()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        self.webView = nil
        isLoading = false
    }

    /// Recreates a suspended tab's web view with its history and scroll position, or loads its address.
    /// A pop-up gets a fresh configuration too, since its tie to the opener can't be restored.
    func restore() {
        guard isSuspended else { return }
        let webView = WKWebView(frame: .zero, configuration: Self.makeConfiguration())
        install(webView, isRestoring: true)
        if let suspendedState {
            webView.interactionState = suspendedState
        } else if let url {
            webView.load(URLRequest(url: url))
        }
        suspendedState = nil
    }

    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")
        let safariVersion = safariURL.flatMap { Bundle(url: $0)?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
            ?? "\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).0"
        configuration.applicationNameForUserAgent = "Version/\(safariVersion) Safari/605.1.15"
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.preferences.isTextInteractionEnabled = true
        WebInspector.enableDeveloperExtras(in: configuration)
        return configuration
    }

    /// Mirrors a KVO-observable web view property into observable state.
    private func observe<Value>(_ webView: WKWebView, _ keyPath: KeyPath<WKWebView, Value>,
                                _ options: NSKeyValueObservingOptions,
                                update: @escaping @MainActor (BrowserTab, WKWebView) -> Void) {
        observations.append(webView.observe(keyPath, options: options) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                update(self, webView)
                self.updateHistory()
            }
        })
    }

    /// The back-forward list has no KVO of its own, but every change to it also changes one of the observed properties.
    private func updateHistory() {
        guard let list = webView?.backForwardList else { return }
        if backList != list.backList { backList = list.backList }
        if forwardList != list.forwardList { forwardList = list.forwardList }
    }

    var title: String {
        if !pageTitle.isEmpty { return pageTitle }
        return url?.host() ?? "New Tab"
    }

    var host: String? {
        url?.host()
    }

    var isSecure: Bool {
        url?.scheme == "https" && hasOnlySecureContent
    }

    func load(_ url: URL) {
        isNewTab = false
        restore()
        webView?.load(URLRequest(url: url))
    }

    /// Captures the visible page for hover cards. Only a web view that's on screen has anything to capture.
    func captureThumbnail(afterScreenUpdates: Bool = true) {
        guard !isNewTab, let webView, webView.window != nil,
              webView.bounds.width > 0, webView.bounds.height > 0 else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        configuration.snapshotWidth = 520
        configuration.afterScreenUpdates = afterScreenUpdates
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            guard let image else { return }
            self?.thumbnail = Image(nsImage: image)
        }
    }

    private func scheduleThumbnail() {
        thumbnailTask?.cancel()
        thumbnailTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.captureThumbnail()
        }
    }

    /// Reads the icon from the loaded page, showing the host's last known icon until then.
    private func updateFavicon() {
        faviconTask?.cancel()
        guard let url, let host = url.host(), url.scheme == "http" || url.scheme == "https" else {
            favicon = nil
            faviconHost = nil
            return
        }
        if faviconHost != host {
            faviconHost = host
            favicon = FaviconStore.cachedIcon(for: url)
        }
        faviconTask = Task { [weak self] in
            // Pages often set their icon from script just after loading or changing their URL.
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled, let webView, !webView.isLoading, webView.url == url else { return }
            let candidates = await FaviconStore.candidates(in: webView)
            guard let icon = await FaviconStore.icon(forPage: url, candidates: candidates),
                  !Task.isCancelled, self.url == url else { return }
            favicon = icon
        }
    }
}

/// Shows one of several page views, such as the active tab's, inside a view this app owns.
/// Swapping the subview never reloads the page, and AppKit guarantees a view has only one superview.
struct PageHost: NSViewRepresentable {
    let content: NSView

    func makeNSView(context: Context) -> PageHostView {
        PageHostView()
    }

    func updateNSView(_ view: PageHostView, context: Context) {
        view.show(content)
    }
}

final class PageHostView: NSView {
    func show(_ content: NSView) {
        guard content.superview !== self else { return }
        subviews.forEach { $0.removeFromSuperview() }
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)
    }
}
