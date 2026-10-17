import AppKit
import SwiftUI

extension BrowserModel {
    var splitViewActions: [BrowserContextAction] {
        var actions: [BrowserContextAction] = []
        if isSplitView {
            actions += [
                .init(title: "Focus Other Pane", icon: .splitView) { self.focusOtherSplitPane() },
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
