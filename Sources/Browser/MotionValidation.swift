import AppKit
import QuartzCore
import SwiftUI
import WebKit

/// Repeatable rendered workloads for Instruments, restricted to the isolated Release QA bundle.
/// These intervals include animation settling; model timings alone cannot measure frame pacing.
@MainActor
enum MotionValidation {
    /// Isolate menu graph invalidation while keeping the measured window unchanged.
    static let omitsCommands = ReleaseValidation.isQA
        && ProcessInfo.processInfo.environment["LISIERE_QA_OMIT_COMMANDS"] == "1"
    @Observable final class ChromeControl {
        var omittedRegion = ""
    }
    static let chromeControl = ChromeControl()
    static var omittedChrome: String { ReleaseValidation.isQA ? chromeControl.omittedRegion : "" }

    static func run(profiles: ProfileStore, owner: ProfileWindowController, base: URL, root: URL) async throws {
        guard ReleaseValidation.isQA, let window = owner.window else { return }
        let distinctURLs = ProcessInfo.processInfo.environment["LISIERE_QA_MOTION_DISTINCT_URLS"] == "1"
        let nativePageControl = ProcessInfo.processInfo.environment["LISIERE_QA_NATIVE_PAGE_CONTROL"] == "1"
        let displayLinkControl = ProcessInfo.processInfo.environment["LISIERE_QA_DISPLAY_LINK_CONTROL"] == "1"
        let profileIdleControl = ProcessInfo.processInfo.environment["LISIERE_QA_PROFILE_IDLE_CONTROL"] == "1"
        let profilePause: Duration = .milliseconds(profileIdleControl ? 800 : 300)
        let omittedChrome = ProcessInfo.processInfo.environment["LISIERE_QA_OMIT_CHROME"] ?? ""
        defer { chromeControl.omittedRegion = "" }
        func webURL(_ page: String) -> URL {
            let url = base.appending(path: "motion")
            return distinctURLs ? url.appending(queryItems: [URLQueryItem(name: "page", value: page)]) : url
        }
        window.setContentSize(NSSize(width: 1000, height: 700))
        window.center()
        // An occluded window can skip presentation while its model continues changing.
        // Keep only this isolated QA window visible throughout a command-line capture.
        window.level = .floating
        window.orderFrontRegardless()
        let displayProbe = displayLinkControl ? DisplayLinkProbe() : nil
        let displayLink = displayProbe.flatMap { probe in
            window.contentView?.displayLink(target: probe, selector: #selector(DisplayLinkProbe.tick(_:)))
        }
        if let displayLink {
            let rate = Float(window.screen?.maximumFramesPerSecond ?? 60)
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
            displayLink.add(to: .main, forMode: .common)
        }
        defer { displayLink?.invalidate() }
        let browser = owner.browser
        browser.preferences.tabLayout = .horizontal
        browser.preferences.showsMascot = true
        let firstID = browser.profileID!
        let second = try profiles.create(name: "Motion second")
        owner.switchTo(second.id)
        owner.browser.preferences.tabLayout = .horizontal
        owner.switchTo(firstID)
        let group = browser.createGroup(name: "Motion", color: .green, tabID: browser.activeTabID)
        for _ in 0..<4 { browser.addTab(in: group) }
        browser.addTab()
        browser.open(webURL("first"))
        let deadline = ContinuousClock.now + .seconds(15)
        while browser.activeTab?.isLoading != false || browser.activeTab?.webView?.title != "QA motion" {
            guard ContinuousClock.now < deadline else { throw CocoaError(.fileReadUnknown) }
            try await Task.sleep(for: .milliseconds(25))
        }
        let webTab = browser.activeTab!
        browser.addTab()
        let homeTab = browser.activeTab!
        try await Task.sleep(for: .seconds(1))
        try write(["pid": ProcessInfo.processInfo.processIdentifier,
                   "screen_maximum_fps": window.screen?.maximumFramesPerSecond ?? 0,
                   "distinct_urls": distinctURLs,
                   "native_page_control": nativePageControl,
                   "display_link_control": displayLink != nil,
                   "profile_idle_control": profileIdleControl,
                   "omits_commands": omitsCommands,
                   "omitted_chrome": omittedChrome,
                   "interaction_driver_version": 2,
                   "width": window.frame.width, "height": window.frame.height], to: root.appending(path: "motion-ready.json"))
        let startDeadline = ContinuousClock.now + .seconds(60)
        while !FileManager.default.fileExists(atPath: root.appending(path: "motion-go").path) {
            guard ContinuousClock.now < startDeadline else { throw CocoaError(.fileReadUnknown) }
            try await Task.sleep(for: .milliseconds(25))
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(500))
        var phases: [[String: Any]] = []
        func phase(_ name: String, count: Int, pause: Duration = .milliseconds(300),
                   action: (Int) -> Void) async throws {
            displayProbe?.reset()
            let start = Date().timeIntervalSince1970
            var active = NSApp.isActive && window.isKeyWindow
            var visible = window.occlusionState.contains(.visible)
            let interval = BrowserDiagnostics.performance.beginInterval("Motion scenario", "\(name, privacy: .public)")
            var actions: [[String: Any]] = []
            for index in 0..<count {
                let actionStart = Date().timeIntervalSince1970
                action(index)
                actions.append(["index": index, "start_epoch": actionStart,
                                "mutation_ms": (Date().timeIntervalSince1970 - actionStart) * 1000])
                try await Task.sleep(for: pause)
                active = active && NSApp.isActive && window.isKeyWindow
                visible = visible && window.occlusionState.contains(.visible)
            }
            try await Task.sleep(for: .milliseconds(500))
            BrowserDiagnostics.performance.endInterval("Motion scenario", interval)
            var result: [String: Any] = ["name": name, "start_epoch": start, "end_epoch": Date().timeIntervalSince1970,
                           "actions": count, "action_timings": actions,
                           "first_responder_type": window.firstResponder.map { String(describing: type(of: $0)) } ?? "",
                           "window_active": active && NSApp.isActive && window.isKeyWindow,
                           "window_visible": visible && window.occlusionState.contains(.visible)]
            if let displayProbe { result["native_callback_cadence"] = displayProbe.summary }
            phases.append(result)
        }
        // Positive control: a deliberately blocked main thread during active motion must be visible
        // to Instruments. Never interpret an empty/unsupported capture as zero dropped frames.
        try await phase("detector-control", count: 5) { _ in
            browser.toggleGroupCollapsed(group)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { blockMainThread() }
        }
        browser.expandGroup(group)
        try await Task.sleep(for: .milliseconds(600))
        try await phase("home-animation", count: 10) { _ in }
        browser.activeTabID = webTab.id
        try await Task.sleep(for: .milliseconds(600))
        try await phase("horizontal-folders", count: 10) { _ in browser.toggleGroupCollapsed(group) }
        browser.preferences.tabLayout = .vertical
        try await Task.sleep(for: .milliseconds(600))
        try await phase("sidebar-folders", count: 10) { _ in browser.toggleGroupCollapsed(group) }
        browser.preferences.tabLayout = .horizontal
        try await Task.sleep(for: .milliseconds(600))
        try await phase("tab-switch", count: 10) { index in browser.activeTabID = index.isMultiple(of: 2) ? homeTab.id : webTab.id }
        try await phase("new-close-tab", count: 10) { index in
            if index.isMultiple(of: 2) { browser.addTab() } else { browser.closeActiveTab() }
        }
        browser.activeTabID = webTab.id
        try await phase("find-bar", count: 10) { _ in
            if webTab.isFindBarVisible { browser.closeFindBar() }
            else { browser.showFindBar() }
        }
        try await phase("profile-switch", count: 10, pause: profilePause) { index in owner.switchTo(index.isMultiple(of: 2) ? second.id : firstID) }
        if ProcessInfo.processInfo.environment["LISIERE_QA_MOTION_EXTENDED"] == "1" {
            // Ablate only the extended web-switch scenarios, after the positive detector and
            // full-interface workloads. Empty regions keep the native page's geometry unchanged.
            chromeControl.omittedRegion = omittedChrome
            browser.open(webURL("second"), inNewTab: true)
            let secondWebTab = browser.activeTab!
            try await waitForPage(secondWebTab)
            try await Task.sleep(for: .milliseconds(600))
            try await phase("tab-switch-web", count: 10) { index in
                browser.activeTabID = index.isMultiple(of: 2) ? webTab.id : secondWebTab.id
            }
            owner.switchTo(second.id)
            owner.browser.open(webURL("other-profile"))
            let otherProfilePage = owner.browser.activeTab!
            try await waitForPage(otherProfilePage)
            owner.switchTo(firstID)
            try await Task.sleep(for: .milliseconds(600))
            try await phase("profile-switch-web", count: 10, pause: profilePause) { index in
                owner.switchTo(index.isMultiple(of: 2) ? second.id : firstID)
            }
            // Read after the measured interval. A visually parked profile must also stop
            // presenting its web page; opacity alone can leave WebKit treating it as visible.
            phases[phases.count - 1]["active_page_visibility"] =
                await probe("return document.visibilityState", in: browser.activeTab!)
            phases[phases.count - 1]["page_animation_callbacks_json"] = await probe("""
                return await new Promise(resolve => {
                    const intervals = [];
                    let previous;
                    const timeout = setTimeout(() => resolve(JSON.stringify({error: "timeout", samples: intervals.length})), 4000);
                    function tick(now) {
                        if (previous !== undefined) intervals.push(now - previous);
                        previous = now;
                        if (intervals.length < 120) return requestAnimationFrame(tick);
                        clearTimeout(timeout);
                        const sorted = [...intervals].sort((a, b) => a - b);
                        resolve(JSON.stringify({samples: intervals.length, median_ms: sorted[60], p95_ms: sorted[114],
                                 maximum_ms: sorted[119], mean_ms: intervals.reduce((a,b) => a+b,0) / intervals.length,
                                 visibility: document.visibilityState}));
                    }
                    requestAnimationFrame(tick);
                });
                """, in: browser.activeTab!)
            phases[phases.count - 1]["parked_page_visibility"] =
                await probe("return document.visibilityState", in: otherProfilePage)
            phases[phases.count - 1]["parked_native_hidden"] = otherProfilePage.webView?.isHiddenOrHasHiddenAncestor ?? false

            if nativePageControl {
                // Diagnostic only: swap the same native pages while leaving chrome selection
                // unchanged. This separates PageHost/WebKit work from SwiftUI chrome updates.
                guard let selected = browser.activeTab,
                      let host = selected.contentView.superview as? PageHostView,
                      let firstView = webTab.webView as? BrowserWebView,
                      let secondView = secondWebTab.webView as? BrowserWebView else {
                    throw CocoaError(.fileReadUnknown)
                }
                // Native focus normally updates the model's selection. Suppress that callback
                // only for this isolated control, and restore both owners even if it fails.
                firstView.tab = nil
                secondView.tab = nil
                defer {
                    host.show(selected.contentView, tab: selected, browser: browser)
                    firstView.tab = webTab
                    secondView.tab = secondWebTab
                }
                try await phase("native-page-switch-control", count: 10) { index in
                    let page = index.isMultiple(of: 2) ? webTab : secondWebTab
                    host.show(page.contentView, tab: page, browser: browser)
                }
                // Restore the preview work performed by a real selection without changing
                // SwiftUI selection. A snapshot can cost rendering time outside its caller.
                var previous = secondWebTab
                try await phase("native-page-preview-control", count: 10) { index in
                    let page = index.isMultiple(of: 2) ? webTab : secondWebTab
                    previous.captureThumbnail(afterScreenUpdates: false)
                    host.show(page.contentView, tab: page, browser: browser)
                    previous = page
                }
                guard browser.activeTab === selected else { throw CocoaError(.fileReadUnknown) }
            }
        }
        try write(["phases": phases, "pid": ProcessInfo.processInfo.processIdentifier], to: root.appending(path: "motion-phases.json"))
        // Keep the process alive until the recorder has detached, without recording shutdown as UI work.
        let stopDeadline = ContinuousClock.now + .seconds(60)
        while !FileManager.default.fileExists(atPath: root.appending(path: "motion-stop").path), ContinuousClock.now < stopDeadline {
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    /// WebKit may suspend a parked process. Bound probes on the native clock so a page timer
    /// cannot stall the whole capture, and record that timeout instead of treating it as a result.
    private static func probe(_ script: String, in tab: BrowserTab) async -> String {
        guard let webView = tab.webView else { return "missing page" }
        return await withCheckedContinuation { continuation in
            let result = ProbeCompletion(continuation)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { result.finish("native timeout") }
            webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { value in
                switch value {
                case .success(let value): result.finish(value as? String ?? "unexpected result")
                case .failure: result.finish("script failed")
                }
            }
        }
    }

    private final class ProbeCompletion {
        private var continuation: CheckedContinuation<String, Never>?
        init(_ continuation: CheckedContinuation<String, Never>) { self.continuation = continuation }
        func finish(_ value: String) {
            continuation?.resume(returning: value)
            continuation = nil
        }
    }

    private static func waitForPage(_ tab: BrowserTab) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while tab.isLoading || tab.webView?.title != "QA motion" {
            guard ContinuousClock.now < deadline else { throw CocoaError(.fileReadUnknown) }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private static func write(_ value: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }

    private static func blockMainThread() { Thread.sleep(forTimeInterval: 0.1) }

    /// Diagnostic only. Callback cadence is not a count of presented frames. This deliberately
    /// requests the screen's maximum refresh rate; normal releases never start this display link.
    @MainActor
    private final class DisplayLinkProbe: NSObject {
        private var lastFrame: CFTimeInterval?
        private var lastDelivery: CFTimeInterval?
        private var frames: [Double] = []
        private var deliveries: [Double] = []

        func reset() {
            lastFrame = nil
            lastDelivery = nil
            frames.removeAll(keepingCapacity: true)
            deliveries.removeAll(keepingCapacity: true)
        }

        @objc func tick(_ link: CADisplayLink) {
            let now = CACurrentMediaTime()
            if let lastFrame { frames.append((link.timestamp - lastFrame) * 1000) }
            if let lastDelivery { deliveries.append((now - lastDelivery) * 1000) }
            lastFrame = link.timestamp
            lastDelivery = now
        }

        var summary: [String: Any] {
            func statistics(_ values: [Double]) -> [String: Any] {
                let sorted = values.sorted()
                guard !sorted.isEmpty else { return ["samples": 0] }
                return ["samples": sorted.count, "median_ms": sorted[sorted.count / 2],
                        "p95_ms": sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))],
                        "maximum_ms": sorted.last!, "mean_ms": sorted.reduce(0, +) / Double(sorted.count)]
            }
            return ["frame_timestamps": statistics(frames), "callback_delivery": statistics(deliveries)]
        }
    }
}
