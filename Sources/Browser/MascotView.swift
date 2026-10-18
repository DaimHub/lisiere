import AppKit
import SwiftUI

/// Animates the original transparent artwork in separate body, eye and pupil layers.
struct MascotView: View {
    let mascot: Mascot
    let palette: MascotPalette
    @Environment(\.browserReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var gaze = CGSize.zero

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || scenePhase != .active)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let bob = reduceMotion ? 0 : sin(time * 1.5) * 2
            let phase = time.truncatingRemainder(dividingBy: 5.7)
            let blink = reduceMotion || phase > 0.22 ? 1 : max(0.08, abs(phase - 0.11) / 0.11)
            ZStack {
                layer("body")
                ZStack {
                    layer("eyes")
                    layer("pupils")
                        .offset(x: mascot.eyeGeometry.centerOffset.width + gaze.width,
                                y: mascot.eyeGeometry.centerOffset.height + gaze.height)
                        .mask(layer("eyes"))
                }
                .scaleEffect(x: 1, y: blink, anchor: mascot.eyeGeometry.anchor)
            }
            .offset(y: bob)
        }
        .frame(width: 120, height: 120)
        .background {
            if !reduceMotion { MascotPointerTracker(gaze: $gaze) }
        }
        .onChange(of: reduceMotion) { _, reduced in if reduced { gaze = .zero } }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func layer(_ name: String) -> some View {
        Image("\(mascot.imageName(for: palette))-\(name)")
            .resizable()
            .scaledToFit()
            .frame(width: 120, height: 120)
    }
}

private struct MascotPointerTracker: NSViewRepresentable {
    @Binding var gaze: CGSize

    func makeNSView(context: Context) -> MascotPointerView {
        let view = MascotPointerView()
        view.onGazeChange = { gaze = $0 }
        return view
    }

    func updateNSView(_ view: MascotPointerView, context: Context) {
        view.onGazeChange = { gaze = $0 }
    }

    static func dismantleNSView(_ view: MascotPointerView, coordinator: ()) {
        view.stopTracking()
        view.onGazeChange = nil
    }
}

/// Tracks only this window's content area, without global event monitors or intercepting clicks.
private final class MascotPointerView: NSView {
    var onGazeChange: ((CGSize) -> Void)?
    private weak var trackedView: NSView?
    private var pointerTrackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopTracking()
        guard let window, let contentView = window.contentView else { return }
        window.acceptsMouseMovedEvents = true

        // inVisibleRect automatically follows resizing; activeInKeyWindow keeps other windows still.
        let area = NSTrackingArea(rect: .zero,
                                  options: [.inVisibleRect, .mouseMoved, .mouseEnteredAndExited,
                                            .activeInKeyWindow, .enabledDuringMouseDrag],
                                  owner: self, userInfo: nil)
        contentView.addTrackingArea(area)
        trackedView = contentView
        pointerTrackingArea = area
    }

    func stopTracking() {
        if let pointerTrackingArea { trackedView?.removeTrackingArea(pointerTrackingArea) }
        pointerTrackingArea = nil
        trackedView = nil
    }

    override func mouseMoved(with event: NSEvent) { follow(event) }
    override func mouseDragged(with event: NSEvent) { follow(event) }
    override func mouseEntered(with event: NSEvent) { follow(event) }
    override func mouseExited(with event: NSEvent) { onGazeChange?(.zero) }

    private func follow(_ event: NSEvent) {
        guard event.window === window else { return }
        let location = convert(event.locationInWindow, from: nil)
        let dx = location.x - bounds.midX
        let dy = location.y - (bounds.midY + 7)
        let distance = max(100, hypot(dx, dy))
        onGazeChange?(CGSize(width: dx / distance * 4, height: dy / distance * 3))
    }
}
