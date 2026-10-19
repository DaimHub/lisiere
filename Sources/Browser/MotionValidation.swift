import AppKit
import SwiftUI

/// Repeatable rendered workloads for Instruments, restricted to the isolated Release QA bundle.
/// These intervals include animation settling; model timings alone cannot measure frame pacing.
@MainActor
enum MotionValidation {
    static func run(profiles: ProfileStore, owner: ProfileWindowController, base: URL, root: URL) async throws {
        guard ReleaseValidation.isQA, let window = owner.window else { return }
        window.setContentSize(NSSize(width: 1000, height: 700))
        window.center()
        // An occluded window can skip presentation while its model continues changing.
        // Keep only this isolated QA window visible throughout a command-line capture.
        window.level = .floating
        window.orderFrontRegardless()
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
        browser.open(base.appending(path: "motion"))
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
        func phase(_ name: String, count: Int, action: (Int) -> Void) async throws {
            let start = Date().timeIntervalSince1970
            var active = NSApp.isActive && window.isKeyWindow
            let interval = BrowserDiagnostics.performance.beginInterval("Motion scenario", "\(name, privacy: .public)")
            for index in 0..<count {
                action(index)
                try await Task.sleep(for: .milliseconds(300))
                active = active && NSApp.isActive && window.isKeyWindow
            }
            try await Task.sleep(for: .milliseconds(500))
            BrowserDiagnostics.performance.endInterval("Motion scenario", interval)
            phases.append(["name": name, "start_epoch": start, "end_epoch": Date().timeIntervalSince1970,
                           "actions": count, "window_active": active && NSApp.isActive && window.isKeyWindow])
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
        try await phase("find-bar", count: 10) { _ in webTab.isFindBarVisible.toggle() }
        try await phase("profile-switch", count: 10) { index in owner.switchTo(index.isMultiple(of: 2) ? second.id : firstID) }
        try write(["phases": phases, "pid": ProcessInfo.processInfo.processIdentifier], to: root.appending(path: "motion-phases.json"))
        // Keep the process alive until the recorder has detached, without recording shutdown as UI work.
        let stopDeadline = ContinuousClock.now + .seconds(60)
        while !FileManager.default.fileExists(atPath: root.appending(path: "motion-stop").path), ContinuousClock.now < stopDeadline {
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private static func write(_ value: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }

    private static func blockMainThread() { Thread.sleep(forTimeInterval: 0.1) }
}
