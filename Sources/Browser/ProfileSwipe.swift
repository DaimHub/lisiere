import AppKit
import SwiftUI

/// One intentional horizontal trackpad gesture changes one profile. Vertical scrolling and momentum pass through.
struct ProfileSwipeState {
    private var tracking = false
    private var horizontal = false
    private var vertical = false
    private var fired = false
    private var x: CGFloat = 0
    private var y: CGFloat = 0

    mutating func consume(dx: CGFloat, dy: CGFloat, phase: NSEvent.Phase, momentum: NSEvent.Phase,
                          precise: Bool) -> (handled: Bool, direction: Int?) {
        guard precise, momentum.isEmpty else { return (false, nil) }
        if phase.contains(.began) {
            self = ProfileSwipeState()
            tracking = true
        }
        guard tracking else { return (false, nil) }
        if phase.contains(.cancelled) || phase.contains(.ended) {
            let handled = horizontal
            self = ProfileSwipeState()
            return (handled, nil)
        }
        x += dx
        y += dy
        if !horizontal && !vertical {
            if abs(y) > 10 && abs(y) > abs(x) { vertical = true }
            else if abs(x) > 10 && abs(x) > abs(y) * 1.5 { horizontal = true }
        }
        guard horizontal else { return (false, nil) }
        guard !fired, abs(x) >= 70 else { return (true, nil) }
        fired = true
        return (true, x < 0 ? 1 : -1)
    }
}

/// A non-hit-testing native view limits the local event monitor to this window's tab strip/sidebar.
struct ProfileSwipeArea: NSViewRepresentable {
    var enabled: Bool
    var switchProfile: (Int) -> Void

    func makeNSView(context: Context) -> ProfileSwipeView { ProfileSwipeView() }
    func updateNSView(_ view: ProfileSwipeView, context: Context) {
        view.enabled = enabled
        view.switchProfile = switchProfile
    }
    static func dismantleNSView(_ view: ProfileSwipeView, coordinator: ()) { view.stopMonitoring() }
}

final class ProfileSwipeView: NSView {
    var enabled = false
    var switchProfile: ((Int) -> Void)?
    private var monitor: Any?
    private var gesture = ProfileSwipeState()

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return handled ? nil : event
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        gesture = ProfileSwipeState()
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard enabled, let window, event.window === window, window.isKeyWindow,
              bounds.contains(convert(event.locationInWindow, from: nil)), !isHiddenOrHasHiddenAncestor else {
            gesture = ProfileSwipeState()
            return false
        }
        let result = gesture.consume(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY,
                                     phase: event.phase, momentum: event.momentumPhase,
                                     precise: event.hasPreciseScrollingDeltas)
        if let direction = result.direction { switchProfile?(direction) }
        return result.handled
    }
}
