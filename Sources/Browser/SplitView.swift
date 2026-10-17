import AppKit
import SwiftUI

extension BrowserModel {
    var splitViewActions: [BrowserContextAction] {
        var actions: [BrowserContextAction] = []
        if hasSplitPair {
            if isSplitView {
                actions.append(.init(title: "Focus Other Pane", icon: .splitView) { self.focusOtherSplitPane() })
            } else {
                actions.append(.init(title: "Return to Split View", icon: .splitView) {
                    self.activeTabID = self.splitTabIDs.first
                })
            }
            actions += [
                .init(title: "Exit Split View", icon: .window) { self.endSplitView() },
                .separator,
            ]
        }
        actions.append(.init(title: "Open New Tab Beside Current Page", icon: .add) { self.startSplitView() })
        let candidates = tabs.filter { $0.id != activeTabID }
        if !candidates.isEmpty {
            actions.append(.init(title: "Choose Tab", icon: .window, children: candidates.map { tab in
                .init(title: tab.title, icon: .window) { self.startSplitView(with: tab.id) }
            }))
        }
        return actions
    }
}

/// Records the native divider without replacing SwiftUI's split-view delegate or drag behavior.
/// Recreated split views restore this window's fraction after their initial layout.
struct SplitDividerPosition: NSViewRepresentable {
    let browser: BrowserModel

    func makeNSView(context: Context) -> SplitDividerPositionView { SplitDividerPositionView() }
    func updateNSView(_ view: SplitDividerPositionView, context: Context) { view.configure(browser) }
    static func dismantleNSView(_ view: SplitDividerPositionView, coordinator: ()) { view.disconnect() }
}

final class SplitDividerPositionView: NSView {
    private weak var browser: BrowserModel?
    private weak var splitView: NSSplitView?
    private var pairIDs: [UUID] = []
    private var restored = false
    private var connecting = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(_ browser: BrowserModel) {
        if pairIDs != browser.splitTabIDs {
            disconnect()
            pairIDs = browser.splitTabIDs
        }
        self.browser = browser
        scheduleConnection()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { disconnect() } else { scheduleConnection() }
    }

    override func layout() {
        super.layout()
        if !restored { scheduleConnection() }
    }

    private func scheduleConnection() {
        guard !connecting, !restored else { return }
        connecting = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.connecting = false
            self.connect()
        }
    }

    private func connect() {
        guard window != nil, let browser, browser.isSplitView, browser.splitTabIDs == pairIDs else { return }
        var ancestor = superview
        while let view = ancestor, !(view is NSSplitView) { ancestor = view.superview }
        guard let split = ancestor as? NSSplitView, split.arrangedSubviews.count == 2,
              split.bounds.width - split.dividerThickness >= 360 else { return }
        if splitView !== split {
            disconnect()
            splitView = split
            NotificationCenter.default.addObserver(self, selector: #selector(dividerResized),
                name: NSSplitView.didResizeSubviewsNotification, object: split)
        }
        guard !restored else { return }
        split.setPosition(browser.splitDividerFraction * (split.bounds.width - split.dividerThickness),
                          ofDividerAt: 0)
        restored = true
    }

    @objc private func dividerResized(_ notification: Notification) {
        guard restored, window != nil, let splitView, let browser,
              browser.isSplitView, browser.splitTabIDs == pairIDs,
              let leading = splitView.arrangedSubviews.first else { return }
        let available = splitView.bounds.width - splitView.dividerThickness
        guard available > 0 else { return }
        let fraction = leading.frame.width / available
        let pair = pairIDs
        // Native layout notifications can arrive during SwiftUI updates.
        DispatchQueue.main.async { [weak self, weak browser] in
            guard let self, self.window != nil, self.restored,
                  let browser, browser.isSplitView, browser.splitTabIDs == pair else { return }
            browser.splitDividerFraction = fraction
        }
    }

    func disconnect() {
        NotificationCenter.default.removeObserver(self)
        splitView = nil
        restored = false
    }

    isolated deinit { disconnect() }
}

/// Activates the pane before AppKit delivers a click, including WebKit content and context menus.
/// It observes only this pane's window/rectangle and never consumes or delays the original event.
struct SplitPaneActivation: NSViewRepresentable {
    let activate: () -> Void

    func makeNSView(context: Context) -> SplitPaneActivationView { SplitPaneActivationView() }
    func updateNSView(_ view: SplitPaneActivationView, context: Context) { view.activate = activate }
    static func dismantleNSView(_ view: SplitPaneActivationView, coordinator: ()) { view.stopObserving() }
}

final class SplitPaneActivationView: NSView {
    var activate: (() -> Void)?
    private var monitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let window = self.window, event.window === window,
                      !self.isHiddenOrHasHiddenAncestor,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return }
                self.activate?()
            }
            return event
        }
    }

    func stopObserving() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    isolated deinit { stopObserving() }
}
