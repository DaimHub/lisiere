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
    var showsHomePage = false
    /// Pinning protects the tab from closure, not from background memory reclamation.
    var isPinned = false
    var groupID: UUID?
    /// The tab whose page opened this one, so its links and pop-ups open next to each other.
    @ObservationIgnored var openerID: UUID?
    /// Whether another page's script opened this one, and can still reach it through `window.opener`.
    @ObservationIgnored var isPopUp = false
    @ObservationIgnored weak var browser: BrowserModel?
    /// When the tab was last selected, so the least recently used tabs are suspended first.
    @ObservationIgnored var lastActive = ContinuousClock.now
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
    /// Why the page couldn't load, shown in place of it until another page loads.
    private(set) var loadError: PageLoadError?
    /// Whether the failed load left the previous page behind the error, so going back shows that page.
    @ObservationIgnored private var loadErrorCoversPreviousPage = false
    private(set) var pageZoom = 1.0

    /// Whether the page has a password field, so saved passwords for its site can be offered.
    var hasPasswordFields = false

    var isFindBarVisible = false
    var findText = ""
    /// Whether the last search found nothing, shown in the find bar.
    private(set) var findHasNoMatches = false
    @ObservationIgnored private var findTask: Task<Void, Never>?
    /// The page last added to history, so its title follows the page's and a reload isn't another visit.
    @ObservationIgnored private var historyVisit: (id: UUID?, url: URL)?

    @ObservationIgnored private let appearance: AppearanceStore
    @ObservationIgnored private let pageDelegate = PageDelegate()
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var thumbnailTask: Task<Void, Never>?
    @ObservationIgnored private var faviconTask: Task<Void, Never>?
    /// The history and scroll position a suspended tab brings back when it's restored.
    @ObservationIgnored private var suspendedState: Any?
    private var faviconHost: String?
    /// Panels the page is waiting to show until the tab is selected.
    @ObservationIgnored private var selectionWaiters: [CheckedContinuation<Bool, Never>] = []
    /// Register before presenting the sheet, so an immediate redirect or window.close() waits too.
    @ObservationIgnored private var passwordPrompts: Set<UUID> = []
    @ObservationIgnored private var passwordDecisionWaiters: [CheckedContinuation<Bool, Never>] = []
    @ObservationIgnored private var closesAfterPasswordDecision = false
    @ObservationIgnored private var presentedSheets: Set<NSWindow> = []
    @ObservationIgnored private var acceptsPageRequests = true

    /// Pass the configuration WebKit provides when a page opens a window, so the new page keeps its opener.
    init(configuration: WKWebViewConfiguration = BrowserTab.makeConfiguration(),
         appearance: AppearanceStore = .shared) {
        self.appearance = appearance
        pageDelegate.tab = self
        install(BrowserWebView(frame: .zero, configuration: configuration))
    }

    /// A suspended tab for a page's saved history, such as a duplicated or reopened tab, which loads when it's selected.
    init(url: URL?, title: String, interactionState: Any?, appearance: AppearanceStore = .shared) {
        self.appearance = appearance
        isNewTab = false
        self.url = url
        pageTitle = title
        suspendedState = interactionState
        faviconHost = url?.host()
        // The page is already in history, so loading it again on restore isn't another visit.
        historyVisit = url.map { (nil, $0) }
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
        acceptsPageRequests = true
        (webView as? BrowserWebView)?.tab = self
        appearance.attach(webView)
        webView.isInspectable = true
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.allowsLinkPreview = true
        webView.frame = contentView.bounds
        webView.autoresizingMask = [.width, .height]
        contentView.addSubview(webView)
        webView.navigationDelegate = pageDelegate
        webView.uiDelegate = pageDelegate
        browser?.contentBlocker.attach(webView.configuration.userContentController)
        self.webView = webView

        let options: NSKeyValueObservingOptions = isRestoring ? [] : .initial
        observe(webView, \.url, options) { tab, webView in
            tab.url = tab.loadError?.url ?? webView.url
            // Same-document navigations don't load, but can still change the icon and add to history.
            if !webView.isLoading {
                tab.updateFavicon()
                tab.recordVisit()
            }
        }
        observe(webView, \.title, options) { tab, webView in
            tab.pageTitle = webView.title ?? ""
            tab.updateVisitTitle()
        }
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

    /// Final window closure also releases a blank page and cancels pending page work.
    func close() {
        cancelPendingPageWork()
        thumbnailTask?.cancel()
        faviconTask?.cancel()
        findTask?.cancel()
        observations.forEach { $0.invalidate() }
        observations = []
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
    }

    /// Releases the web view, and with it the page's memory, keeping what the tab strip shows and the state to restore.
    func suspend() {
        guard let webView, !isNewTab else { return }
        cancelPendingPageWork()
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
        let webView = BrowserWebView(frame: .zero, configuration: browser?.makeConfiguration() ?? Self.makeConfiguration())
        install(webView, isRestoring: true)
        if let suspendedState {
            webView.interactionState = suspendedState
        } else if let url {
            Self.load(url, in: webView)
        }
        suspendedState = nil
    }

    /// Whether suspending would lose nothing the page is doing: loading, showing an error or waiting to show a panel,
    /// using the camera or microphone, or being inspected. Pages with unsaved form input aren't detected, since WebKit
    /// has no cheap way to ask; their history still restores.
    var canSuspend: Bool {
        guard let webView, !isNewTab, !isLoading, loadError == nil, selectionWaiters.isEmpty,
              passwordPrompts.isEmpty, presentedSheets.isEmpty else { return false }
        #if DEBUG
        if WebInspector.isOpen(for: webView) { return false }
        #endif
        return webView.cameraCaptureState == .none && webView.microphoneCaptureState == .none
    }

    /// Waits until the tab is selected, so a background page's panel can't take over the window.
    /// Returns `false` if the tab is closed or suspended first.
    func waitUntilSelected() async -> Bool {
        guard acceptsPageRequests, let browser, browser.tab(withID: id) === self else { return false }
        if browser.isActiveInWorkspace, browser.activeTabID == id { return true }
        return await withCheckedContinuation { selectionWaiters.append($0) }
    }

    /// Shows a panel as a sheet on the page's window. A background tab's panel waits until the tab is selected,
    /// so a page can't take over the window, and is dismissed if the tab closes first.
    func present(_ alert: NSAlert, in webView: WKWebView? = nil) async -> NSApplication.ModalResponse? {
        guard let webView = webView ?? self.webView, await waitUntilSelected() else { return nil }
        // The selected tab's page joins the window on SwiftUI's next update.
        for _ in 0..<20 where webView.window == nil {
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard acceptsPageRequests, browser?.tab(withID: id) === self, self.webView === webView,
              let window = webView.window else { return nil }
        let sheet = alert.window
        presentedSheets.insert(sheet)
        defer { presentedSheets.remove(sheet) }
        let response = await alert.beginSheetModal(for: window)
        return browser?.tab(withID: id) === self ? response : nil
    }

    func didBecomeSelected() {
        guard browser?.isActiveInWorkspace == true else { return }
        resumeSelectionWaiters(true)
    }

    /// Also rejects WebKit callbacks already queued when the user closes or suspends the page.
    func cancelPendingPageWork() {
        acceptsPageRequests = false
        resumeSelectionWaiters(false)
        passwordPrompts.removeAll()
        closesAfterPasswordDecision = false
        resumePasswordDecisionWaiters(false)
        for sheet in presentedSheets {
            sheet.sheetParent?.endSheet(sheet, returnCode: .abort)
        }
    }

    /// Keep a pending native decision attached to its original window until it completes.
    var canMoveBetweenWindows: Bool {
        (acceptsPageRequests || isSuspended) && passwordPrompts.isEmpty && presentedSheets.isEmpty && selectionWaiters.isEmpty
    }

    func beginPasswordPrompt() -> UUID {
        let token = UUID()
        passwordPrompts.insert(token)
        return token
    }

    func isPasswordPromptPending(_ token: UUID) -> Bool {
        acceptsPageRequests && passwordPrompts.contains(token)
    }

    func finishPasswordPrompt(_ token: UUID) {
        guard passwordPrompts.remove(token) != nil, passwordPrompts.isEmpty else { return }
        let shouldClose = closesAfterPasswordDecision && !isPinned
        closesAfterPasswordDecision = false
        resumePasswordDecisionWaiters(!shouldClose)
        if shouldClose { browser?.closeTab(id) }
    }

    /// Holds WebKit's original navigation decision; resuming never replays a form submission.
    func waitForPasswordDecision() async -> Bool {
        guard acceptsPageRequests else { return false }
        guard !passwordPrompts.isEmpty else { return true }
        let canContinue = await withCheckedContinuation { passwordDecisionWaiters.append($0) }
        return canContinue && acceptsPageRequests && browser?.tab(withID: id) === self
    }

    /// Automatic popup closure must leave time to answer Save, Not Now, or Never.
    /// An explicit user close still goes straight through BrowserModel.closeTab.
    func requestCloseFromPage() {
        guard !isPinned else { return }
        guard passwordPrompts.isEmpty else {
            closesAfterPasswordDecision = true
            return
        }
        browser?.closeTab(id)
    }

    private func resumePasswordDecisionWaiters(_ canContinue: Bool) {
        let waiters = passwordDecisionWaiters
        passwordDecisionWaiters = []
        waiters.forEach { $0.resume(returning: canContinue) }
    }

    private func resumeSelectionWaiters(_ isSelected: Bool) {
        let waiters = selectionWaiters
        selectionWaiters = []
        waiters.forEach { $0.resume(returning: isSelected) }
    }

    /// WebKit only answers this asynchronously, so it's checked separately from `canSuspend`.
    func isPlayingMedia() async -> Bool {
        await webView?.requestMediaPlaybackState() == .playing
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
        #if DEBUG
        WebInspector.enableDeveloperExtras(in: configuration)
        #endif
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
        url?.scheme == "https" && hasOnlySecureContent && loadError == nil
    }

    /// Going back from an error that covers the previous page shows that page, which is still the current history item.
    var canNavigateBack: Bool {
        canGoBack || (loadError != nil && loadErrorCoversPreviousPage)
    }

    func load(_ url: URL) {
        isNewTab = false
        restore()
        pageDelegate.isLoadingFromBrowser = true
        if let webView { Self.load(url, in: webView) }
    }

    /// A local file, such as an HTML file opened from the Finder, may only read itself.
    private static func load(_ url: URL, in webView: WKWebView) {
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url)
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    func reload() {
        if loadError != nil {
            retry()
        } else if let webView {
            pageDelegate.isLoadingFromBrowser = true
            webView.reload()
        } else {
            restore()
        }
    }

    func goBack() {
        if loadError != nil, loadErrorCoversPreviousPage {
            clearLoadError()
        } else {
            webView?.goBack()
        }
    }

    /// A page has started to show in the tab: it gets its site's zoom, and joins history.
    func didCommitNavigation() {
        clearLoadError()
        findHasNoMatches = false
        hasPasswordFields = false
        applyZoom()
        recordVisit()
    }

    /// Adds the page shown to history, unless it's the same page as before, ignoring the part after `#`.
    /// Only committed web pages count, so error pages and pop-ups that never loaded are left out.
    private func recordVisit() {
        guard let webView, let url = webView.url, loadError == nil,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              webView.backForwardList.currentItem?.url == url,
              historyVisit.map({ Self.withoutFragment($0.url) != Self.withoutFragment(url) }) ?? true else { return }
        historyVisit = (browser?.history?.recordVisit(to: url, title: webView.title ?? ""), url)
    }

    private func updateVisitTitle() {
        guard let historyVisit, let id = historyVisit.id, url == historyVisit.url, !pageTitle.isEmpty else { return }
        browser?.history?.updateTitle(of: id, to: pageTitle)
    }

    private static func withoutFragment(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.url ?? url
    }

    // MARK: Zoom

    private func applyZoom() {
        let level = browser?.zoomLevels.level(for: host) ?? 1
        pageZoom = level
        if let webView, webView.pageZoom != level { webView.pageZoom = level }
    }

    /// Zooms the page, and remembers the level for its site.
    func setZoom(_ level: Double) {
        guard let webView else { return }
        webView.pageZoom = level
        pageZoom = level
        browser?.zoomLevels.setLevel(level, for: host)
    }

    // MARK: Find

    /// Searches from the start of the current match, so typing more of a word keeps the match it's on.
    func findAsYouType() {
        findTask?.cancel()
        guard let webView, !findText.isEmpty else {
            findHasNoMatches = false
            return
        }
        findTask = Task { [weak self] in
            let script = "(() => { const selection = getSelection(); if (selection.rangeCount) selection.collapseToStart(); })()"
            _ = try? await webView.evaluateJavaScript(script, contentWorld: .defaultClient)
            guard !Task.isCancelled else { return }
            await self?.runFind(backwards: false)
        }
    }

    func find(backwards: Bool = false) {
        findTask?.cancel()
        findTask = Task { [weak self] in await self?.runFind(backwards: backwards) }
    }

    /// WebKit selects and highlights the match it finds, wrapping around the page.
    private func runFind(backwards: Bool) async {
        guard let webView, !findText.isEmpty else { return }
        let text = findText
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        let result = try? await webView.find(text, configuration: configuration)
        guard !Task.isCancelled, findText == text else { return }
        findHasNoMatches = result?.matchFound != true
    }

    func selectedText() async -> String? {
        guard let webView else { return nil }
        return try? await webView.evaluateJavaScript("getSelection().toString()", contentWorld: .defaultClient) as? String
    }

    /// Gives the page keyboard focus.
    func focusPage() {
        guard let webView, let window = webView.window else { return }
        window.makeFirstResponder(webView)
    }

    func showLoadError(_ error: PageLoadError, coversPreviousPage: Bool) {
        loadError = error
        loadErrorCoversPreviousPage = coversPreviousPage
        url = error.url ?? url
    }

    func clearLoadError() {
        guard loadError != nil else { return }
        loadError = nil
        loadErrorCoversPreviousPage = false
        url = webView?.url
    }

    /// Loads the address that failed again, keeping the error up until a page loads.
    func retry() {
        guard let webView else { return }
        pageDelegate.isLoadingFromBrowser = true
        if let url = loadError?.url {
            webView.load(URLRequest(url: url))
        } else {
            webView.reload()
        }
    }

    /// Captures the visible page for hover cards. Only a web view that's on screen has anything to capture.
    func captureThumbnail(afterScreenUpdates: Bool = true) {
        guard !isNewTab, browser?.isActiveInWorkspace != false,
              let webView, webView.window != nil, !webView.isHiddenOrHasHiddenAncestor,
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

    func restorePinnedFavicon() {
        guard isPinned, isSuspended, favicon == nil, let url,
              let browser, !browser.isPrivate else { return }
        faviconTask?.cancel()
        faviconTask = Task { [weak self, weak browser] in
            let icon = await browser?.favicons.storedIcon(for: url)
            guard let self, !Task.isCancelled, self.url == url, self.favicon == nil else { return }
            self.favicon = icon
        }
    }

    /// Reads the icon from the loaded page, showing the host's last known icon until then.
    private func updateFavicon() {
        faviconTask?.cancel()
        guard browser?.isPrivate != true else {
            favicon = nil
            faviconHost = nil
            return
        }
        guard let url, let host = url.host(), url.scheme == "http" || url.scheme == "https" else {
            favicon = nil
            faviconHost = nil
            return
        }
        if faviconHost != host {
            faviconHost = host
            favicon = browser?.favicons.cachedIcon(for: url)
        }
        faviconTask = Task { [weak self] in
            // Pages often set their icon from script just after loading or changing their URL.
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled, let webView, !webView.isLoading, webView.url == url else { return }
            let candidates = await FaviconStore.candidates(in: webView)
            guard let icon = await browser?.favicons.icon(forPage: url, candidates: candidates,
                                                     remember: !(browser?.isPrivate ?? false)),
                  !Task.isCancelled, self.url == url else { return }
            favicon = icon
        }
    }
}

/// Shows one of several page views, such as the active tab's, inside a view this app owns.
/// Swapping the subview never reloads the page, and AppKit guarantees a view has only one superview.
struct PageHost: NSViewRepresentable {
    let content: NSView
    var tab: BrowserTab? = nil
    var browser: BrowserModel? = nil

    func makeNSView(context: Context) -> PageHostView {
        PageHostView()
    }

    func updateNSView(_ view: PageHostView, context: Context) {
        view.show(content, tab: tab, browser: browser)
    }

    static func dismantleNSView(_ view: PageHostView, coordinator: ()) { view.releaseContent() }
}

final class PageHostView: NSView {
    private var content: NSView?
    private weak var tab: BrowserTab?
    private weak var browser: BrowserModel?
    private var checksOwnership = false
    private var attachmentScheduled = false
    private weak var displayedContent: NSView?
    private weak var displayedTab: BrowserTab?

    func show(_ content: NSView, tab: BrowserTab? = nil, browser: BrowserModel? = nil) {
        let needsReconciliation = self.content !== content || self.tab !== tab || self.browser !== browser
            || content.superview !== self
        self.content = content
        self.tab = tab
        self.browser = browser
        checksOwnership = tab != nil
        attachContent()
        // SwiftUI may update the departing host after its replacement. Reconcile ownership once
        // that transaction has dismantled the old host, without rebuilding/reloading the page.
        guard needsReconciliation, !attachmentScheduled else { return }
        attachmentScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.attachmentScheduled = false
            self.attachContent()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachContent()
    }

    private func attachContent() {
        // A departing SwiftUI host can update again during the last-tab transition.
        // Only the tab's current model may reattach its live page after a window transfer.
        if checksOwnership {
            guard let tab, let browser, tab.browser === browser else { return }
        }
        guard let window, let content else { return }
        let previousHadFocus = displayedContent !== content && displayedContent.map { previous in
            (window.firstResponder as? NSView)?.isDescendant(of: previous) == true
        } == true
        if content.superview !== self {
            // Keep just the last page attached but hidden. Reparenting WebKit on every round trip
            // invalidates the native view hierarchy; its existing window/layers can be reused instead.
            // close()/suspend() remove their own web view, so this does not prevent unloading.
            let canRetainPrevious = displayedTab.map { previous in
                browser != nil && previous.browser === browser && browser?.tab(withID: previous.id) === previous
            } ?? false
            for view in subviews where view !== displayedContent || !canRetainPrevious {
                view.removeFromSuperview()
                view.isHidden = false
            }
            content.frame = bounds
            content.autoresizingMask = [.width, .height]
            addSubview(content)
        }
        for view in subviews {
            let hidden = view !== content
            if view.isHidden != hidden { view.isHidden = hidden }
        }
        displayedContent = content
        displayedTab = tab
        if previousHadFocus {
            window.makeFirstResponder(nil)
            if tab?.isNewTab == false, browser?.isActiveInWorkspace == true { tab?.focusPage() }
        }
    }

    func releaseContent() {
        // A newer host may already own this same page. Never detach it from that host.
        for view in subviews {
            view.removeFromSuperview()
            view.isHidden = false
        }
        displayedTab = nil
        displayedContent = nil
        content = nil
    }
}

/// Keyboard/accessibility focus follows the same active-pane state as pointer activation.
final class BrowserWebView: WKWebView {
    weak var tab: BrowserTab?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, let tab, let browser = tab.browser, browser.isActiveInWorkspace,
           browser.isTabVisible(tab.id), browser.activeTabID != tab.id {
            browser.activeTabID = tab.id
        }
        return accepted
    }
}
