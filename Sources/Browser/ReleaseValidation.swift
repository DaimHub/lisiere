import AppKit
import SwiftUI
import WebKit

private struct BrowserReduceMotionKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    /// Defaults to the system value. QA can exercise both paths without changing macOS preferences.
    var browserReduceMotion: Bool {
        get { self[BrowserReduceMotionKey.self] ?? accessibilityReduceMotion }
        set { self[BrowserReduceMotionKey.self] = newValue }
    }
}

/// Only the QA bundle overrides the accessibility environment; system preferences remain untouched.
struct ReleaseValidationAccessibility: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    func body(content: Content) -> some View {
        content.environment(\.browserReduceMotion, ReleaseValidation.isQA
                            ? ProcessInfo.processInfo.environment["LISIERE_QA_REDUCE_MOTION"] == "1" : systemReduceMotion)
    }
}

/// Internal acceptance driver. Only a separately signed QA copy can enter it; the ordinary bundle ignores it.
/// It exercises the shipping model, WebKit delegates and native window under Release protections.
@MainActor
enum ReleaseValidation {
    static var isQA: Bool {
        Bundle.main.bundleIdentifier?.hasPrefix("io.github.daimhub.lisiere.qa.") == true
    }
    private static var started = false
    private static var checks: [String] = []
    private static var metrics: [String: Double] = [:]
    private static var launchTime = CFAbsoluteTimeGetCurrent()
    static func markLaunch() { launchTime = CFAbsoluteTimeGetCurrent() }
    private struct Failure: Error { let check: String }
    private final class WeakTab {
        weak var value: BrowserTab?
        init(_ value: BrowserTab?) { self.value = value }
    }
    private static var root: URL { StoreFile.applicationSupport(named: "Validation").url }

    static func start(profiles: ProfileStore, owner: ProfileWindowController, reduceMotion: Bool) {
        let environment = ProcessInfo.processInfo.environment
        guard isQA, !started, let phase = environment["LISIERE_QA_VALIDATION"],
              let baseString = environment["LISIERE_QA_BASE_URL"] else { return }
        started = true
        guard let base = URL(string: baseString), base.host() == "127.0.0.1", base.scheme == "http" else { exit(2) }
        Task {
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try await wait("native-window") { owner.window != nil }
                metrics["native_window_ms"] = (CFAbsoluteTimeGetCurrent() - launchTime) * 1000
                owner.window?.makeKeyAndOrderFront(nil)
                NSApp.activate()
                try check(reduceMotion == (environment["LISIERE_QA_REDUCE_MOTION"] == "1"), "reduce-motion-environment")
                if phase == "journey" { try await journey(profiles, owner, base) }
                else if phase == "restore" { try await restore(profiles, owner, base) }
                else { throw Failure(check: "unknown-phase") }
                try report(phase: phase, success: true)
                NSApp.terminate(nil)
            } catch {
                try? report(phase: phase, success: false, failure: (error as? Failure)?.check ?? "unexpected-error")
                exit(1)
            }
        }
    }

    private static func check(_ value: Bool, _ name: String) throws {
        guard value else { throw Failure(check: name) }
        checks.append(name)
        BrowserDiagnostics.lifecycle.info("Release validation passed: \(name, privacy: .public)")
        FileHandle.standardError.write(Data("QA passed: \(name)\n".utf8))
    }
    private static func wait(_ name: String, timeout: Duration = .seconds(15), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { throw Failure(check: name + "-timeout") }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
    private static func load(_ path: String, in browser: BrowserModel, base: URL) async throws {
        let target = base.appending(path: path)
        if browser.activeTab?.url?.path == target.path {
            _ = try await js("document.title = 'QA pending'; true", browser)
        }
        browser.open(target)
        try await wait("load-" + path) {
            browser.activeTab?.url?.path == target.path && browser.activeTab?.isLoading == false
                && browser.activeTab?.webView?.title == "QA " + path
        }
        try check(browser.activeTab?.loadError == nil, "load-" + path)
    }
    private static func js(_ script: String, _ browser: BrowserModel) async throws -> Any? {
        guard let view = browser.activeTab?.webView else { throw Failure(check: "missing-webview") }
        return try await view.evaluateJavaScript(script)
    }

    private static func journey(_ profiles: ProfileStore, _ owner: ProfileWindowController, _ base: URL) async throws {
        let browser = owner.browser
        let context = profiles.context(for: BrowserProfile.initialID)!
        await context.history.waitUntilLoaded()
        await context.contentBlocker.waitUntilLoaded()
        try check(context.contentBlocker.isBlocking(on: "example.test"), "production-tracker-list-installed")
        try await load("one", in: browser, base: base)
        _ = try await js("localStorage.setItem('qa','first'); document.cookie='qa=first; Max-Age=3600; SameSite=Lax; Path=/'; true", browser)
        browser.open(base.appending(path: "redirect"))
        try await wait("redirect") { browser.activeTab?.pageTitle == "QA two" && browser.activeTab?.isLoading == false }
        try check(browser.activeTab?.url?.path == "/two", "redirect")
        browser.goBack()
        try await wait("back") { browser.activeTab?.url?.path == "/one" && browser.activeTab?.isLoading == false }
        browser.goForward()
        try await wait("forward") { browser.activeTab?.url?.path == "/two" && browser.activeTab?.isLoading == false }
        try check(browser.activeTab?.canGoBack == true, "back-forward")
        try await load("form", in: browser, base: base)
        _ = try await js("document.querySelector('input').value='fixture'; document.querySelector('form').requestSubmit(); true", browser)
        try await wait("form-submit") { browser.activeTab?.pageTitle == "QA submitted" && browser.activeTab?.isLoading == false }
        try check(browser.activeTab?.url?.query() == "value=fixture", "form-submit")

        let original = browser.activeTab!.id
        let group = browser.createGroup(name: "QA folder", color: .green, tabID: original)
        browser.addTab(in: group)
        try await load("child", in: browser, base: base)
        let child = browser.activeTab!.id
        browser.collapseGroup(group)
        browser.expandGroup(group)
        browser.startSplitView(with: original)
        try check(browser.isSplitView && browser.tabs.count == 2, "folder-split")
        browser.endSplitView()
        browser.closeTab(child)
        browser.reopenClosedTab()
        try await wait("reopened-tab") { browser.activeTab?.url?.path == "/child" }
        try check(browser.tabs.count == 2, "close-reopen-tab")

        browser.addTab()
        let slowTab = WeakTab(browser.activeTab)
        browser.open(base.appending(path: "slow"))
        browser.closeActiveTab()
        try await wait("closed-loading-tab-released") { slowTab.value == nil }
        checks.append("close-during-slow-response")
        browser.addTab()
        browser.open(base.appending(path: "disconnect"))
        try await wait("network-error") { browser.activeTab?.loadError != nil }
        try await load("recovered", in: browser, base: base)
        browser.closeActiveTab()

        let second = try profiles.create(name: "QA second")
        owner.switchTo(second.id)
        try await load("one", in: owner.browser, base: base)
        let isolated = try await js("localStorage.getItem('qa') === null && !document.cookie.includes('qa=first')", owner.browser)
        try check(isolated as? Bool == true, "profile-cookie-storage-isolation")
        _ = try await js("localStorage.setItem('qa','second'); true", owner.browser)
        var profileTimes: [Double] = []
        for _ in 0..<20 {
            let start = CFAbsoluteTimeGetCurrent()
            owner.switchTo(BrowserProfile.initialID); owner.switchTo(second.id)
            profileTimes.append((CFAbsoluteTimeGetCurrent() - start) * 500)
            await Task.yield()
        }
        metrics["profile_switch_p95_ms"] = profileTimes.sorted()[18]
        owner.switchTo(BrowserProfile.initialID)
        try await load("one", in: browser, base: base)
        let intact = try await js("localStorage.getItem('qa') === 'first'", browser)
        try check(intact as? Bool == true && browser.tabs.count == 2, "profile-switch-preserves-tabs-data")

        let privateBrowser = BrowserModel.makePrivate()
        try await load("one", in: privateBrowser, base: base)
        let privateEmpty = try await js("localStorage.getItem('qa') === null && document.cookie === ''", privateBrowser)
        try check(privateEmpty as? Bool == true && privateBrowser.history == nil && privateBrowser.passwords == nil,
                  "private-window-isolation")
        privateBrowser.releaseClosedWindow()

        let downloadDirectory = root.appending(path: "Downloads")
        try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        let downloads = DownloadManager(directory: downloadDirectory, preferences: context.preferences)
        let downloadBrowser = context.makeBrowser(downloads: downloads)
        downloadBrowser.open(base.appending(path: "download"))
        try await wait("download") { downloads.items.first?.state == .finished }
        guard let downloaded = downloads.items.first?.destinationURL else { throw Failure(check: "download-destination") }
        try check(try Data(contentsOf: downloaded) == Data("Lisiere QA download\n".utf8), "download-bytes")
        downloadBrowser.releaseClosedWindow()
        try FileManager.default.removeItem(at: downloaded)

        try await blocking(context, base)

        try await performance(browser)
        context.bookmarks.add(title: "QA marker", url: base.appending(path: "one"))
        for profile in profiles.availableProfiles {
            guard let context = profiles.context(for: profile.id) else { continue }
            await context.history.waitUntilLoaded()
            context.history.saveNow(); context.session.saveBeforeQuitting()
            try check(context.persistenceFailure == nil, "save-" + (profile.isInitial ? "initial" : "second"))
        }
        UserDefaults.standard.set(second.id.uuidString, forKey: "qaSecondProfile")
        UserDefaults.standard.synchronize()
        // A fixed sleep does not establish that WebKit committed its asynchronous cookie writes.
        // Observe only this fresh QA container's synthetic cookie; never flush, copy or reseed it.
        let cookies = await context.browsingData.dataStore.httpCookieStore.allCookies()
        try check(cookies.contains { $0.name == "qa" && $0.value == "first"
            && $0.domain == "127.0.0.1" && !$0.isSessionOnly && ($0.expiresDate ?? .distantPast) > .now },
                  "persistent-cookie-created")
        let cookieFile = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appending(path: "Cookies/Cookies.binarycookies")
        // macOS CFNetwork stores the fixture's domain/name/path/value as NUL-terminated strings.
        // An unknown storage format fails this precondition instead of passing an unverified restart.
        let marker = Data("127.0.0.1\0qa\0/\0first\0".utf8)
        let cookieStart = CFAbsoluteTimeGetCurrent()
        try await wait("persistent-cookie-durable", timeout: .seconds(45)) {
            (try? Data(contentsOf: cookieFile).range(of: marker)) != nil
        }
        metrics["cookie_persistence_wait_ms"] = (CFAbsoluteTimeGetCurrent() - cookieStart) * 1000
        try check(true, "persistent-cookie-durable")
    }

    private static func restore(_ profiles: ProfileStore, _ owner: ProfileWindowController, _ base: URL) async throws {
        let context = profiles.context(for: BrowserProfile.initialID)!
        await context.history.waitUntilLoaded()
        try check(owner.browser.tabs.count == 2 && owner.browser.groups.first?.name == "QA folder", "restart-tabs-folders")
        try check(!context.history.visits.isEmpty && context.bookmarks.bookmarks.contains { $0.title == "QA marker" },
                  "restart-history-bookmarks")
        try await load("one", in: owner.browser, base: base)
        let first = try await js("[localStorage.getItem('qa') === 'first', document.cookie.includes('qa=first')]", owner.browser) as? [Bool]
        try check(first?.first == true, "restart-local-storage")
        try check(first?.last == true, "restart-persistent-cookie")
        guard let value = UserDefaults.standard.string(forKey: "qaSecondProfile"), let id = UUID(uuidString: value) else {
            throw Failure(check: "restart-profile-id")
        }
        owner.switchTo(id)
        try await load("one", in: owner.browser, base: base)
        let second = try await js("localStorage.getItem('qa') === 'second'", owner.browser)
        try check(second as? Bool == true, "restart-profile-isolation")
        owner.switchTo(BrowserProfile.initialID)
        // Profile deletion requires all owners to release it. Use a fresh unused profile to exercise cleanup.
        let disposable = try profiles.create(name: "QA disposable")
        _ = profiles.context(for: disposable.id)
        try await profiles.delete(disposable.id)
        try check(profiles.profile(disposable.id) == nil, "profile-deletion")
        await context.browsingData.clear(.history, range: .all)
        let saved = StoreFile(url: profiles.directory(for: .initial)!.appending(path: "History.plist"))
        try check(saved.decodeNow([HistoryVisit].self)?.isEmpty == true, "clear-history-durable")
    }

    private static func performance(_ browser: BrowserModel) async throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let pages = (0..<20_000).map {
            HistoryPage(url: URL(string: "https://fixture\($0).test/page")!, title: "Fixture page \($0)", visitCount: 3, lastVisit: now)
        }
        let start = CFAbsoluteTimeGetCurrent()
        let index = AddressSuggestions.Index(pages: pages, bookmarks: [])
        metrics["address_index_20000_ms"] = (CFAbsoluteTimeGetCurrent() - start) * 1000
        var queries: [Double] = []
        for value in 0..<60 {
            let start = CFAbsoluteTimeGetCurrent()
            let result = index.rank("fixture\(value)", now: now)
            queries.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            try check(!result.isEmpty, "query-\(value)")
        }
        metrics["address_query_20000_p95_ms"] = queries.sorted()[56]
        let folder = browser.groups[0].id
        let folderStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<100 { browser.collapseGroup(folder); browser.expandGroup(folder) }
        metrics["folder_toggle_mean_ms"] = (CFAbsoluteTimeGetCurrent() - folderStart) * 5
        let baselineCount = browser.tabs.count
        for cycle in 0..<4 {
            let start = CFAbsoluteTimeGetCurrent()
            for _ in 0..<25 {
                browser.addTab()
                let tab = WeakTab(browser.activeTab)
                browser.closeActiveTab()
                try await wait("tab-release") { tab.value == nil }
            }
            try check(browser.tabs.count == baselineCount, "tab-cycle-\(cycle)")
            metrics["tab_cycle_\(cycle)_ms"] = (CFAbsoluteTimeGetCurrent() - start) * 1000
            try await Task.sleep(for: .milliseconds(300))
            metrics["resident_\(cycle)_bytes"] = residentBytes()
        }
    }

    private static func blocking(_ context: ProfileContext, _ base: URL) async throws {
        // Real production rules, plus one loopback tracker so enforcement needs no external service.
        let blocker = ContentBlocker(store: .default(), identifier: "QA-network", ruleSource: { exceptions in
            var rules = TrackerBlocklist.rules(exceptions: exceptions)
            rules.insert(.init(trigger: .init(urlFilter: "^http://localhost[:/].*/qa-tracker$", loadType: ["third-party"]),
                               action: .init(type: "block")), at: 0)
            return String(decoding: try! JSONEncoder().encode(rules), as: UTF8.self)
        })
        let browser = BrowserModel(websiteDataStore: context.browsingData.dataStore, contentBlocker: blocker)
        defer { browser.releaseClosedWindow() }
        await blocker.waitUntilLoaded()
        try check(blocker.state == .ready, "fixture-rule-compilation")
        try await load("blocking", in: browser, base: base)
        let blocked = try await js("window.trackerResult", browser)
        try check(blocked as? String == "blocked", "network-tracker-blocked")
        await blocker.setBlocking(false, on: "127.0.0.1")
        try await load("blocking", in: browser, base: base)
        let allowed = try await js("window.trackerResult", browser)
        try check(allowed as? String == "loaded", "network-site-exception")
        await blocker.removeCompiledRules()
    }

    private static func residentBytes() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) : -1
    }

    private static func report(phase: String, success: Bool, failure: String? = nil) throws {
        var report: [String: Any] = ["phase": phase, "success": success, "checks": checks, "metrics": metrics,
                                   "reduce_motion": ProcessInfo.processInfo.environment["LISIERE_QA_REDUCE_MOTION"] == "1",
                                   "bundle": Bundle.main.bundleIdentifier!, "os": ProcessInfo.processInfo.operatingSystemVersionString]
        if let failure { report["failure"] = failure }
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
        try data.write(to: root.appending(path: phase + ".json"), options: .atomic)
    }
}
