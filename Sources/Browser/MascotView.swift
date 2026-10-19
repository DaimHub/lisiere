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
        MascotArtwork(mascot: mascot, palette: palette, gaze: gaze,
                      animated: !reduceMotion && scenePhase == .active)
        .frame(width: 120, height: 120)
        .background {
            if !reduceMotion && scenePhase == .active { MascotPointerTracker(gaze: $gaze) }
        }
        .onChange(of: reduceMotion) { _, reduced in if reduced { gaze = .zero } }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

}

private struct MascotArtwork: NSViewRepresentable {
    let mascot: Mascot
    let palette: MascotPalette
    let gaze: CGSize
    let animated: Bool
    func makeNSView(context: Context) -> MascotArtworkView { MascotArtworkView() }
    func updateNSView(_ view: MascotArtworkView, context: Context) {
        view.update(mascot: mascot, palette: palette, gaze: gaze, animated: animated)
    }
}

/// The render server interpolates these transforms at the display cadence. SwiftUI no longer
/// rebuilds the masked artwork thirty (or 120) times a second just to move and blink it.
final class MascotArtworkView: NSView {
    let movingLayer = CALayer()
    let eyeLayer = CALayer()
    private let bodyLayer = CALayer()
    private let whitesLayer = CALayer()
    private let pupilContainer = CALayer()
    private let pupilLayer = CALayer()
    private let pupilMask = CALayer()
    private var artworkName: String?
    private var wantsAnimation = false
    private var animationFrameRate: Float = 0
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(movingLayer)
        movingLayer.addSublayer(bodyLayer)
        movingLayer.addSublayer(eyeLayer)
        eyeLayer.addSublayer(whitesLayer)
        eyeLayer.addSublayer(pupilContainer)
        pupilContainer.addSublayer(pupilLayer)
        pupilContainer.mask = pupilMask
        for image in [bodyLayer, whitesLayer, pupilLayer, pupilMask] { image.contentsGravity = .resizeAspect }
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(mascot: Mascot, palette: MascotPalette, gaze: CGSize, animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let name = mascot.imageName(for: palette)
        if artworkName != name {
            artworkName = name
            bodyLayer.contents = NSImage(named: name + "-body")
            whitesLayer.contents = NSImage(named: name + "-eyes")
            pupilLayer.contents = NSImage(named: name + "-pupils")
            pupilMask.contents = NSImage(named: name + "-eyes")
        }
        let geometry = mascot.eyeGeometry
        eyeLayer.anchorPoint = CGPoint(x: geometry.anchor.x, y: geometry.anchor.y)
        // Layer coordinates follow this flipped NSView, matching SwiftUI's top-left origin.
        pupilLayer.setAffineTransform(CGAffineTransform(translationX: geometry.centerOffset.width + gaze.width,
                                                       y: geometry.centerOffset.height + gaze.height))
        layoutArtwork()
        CATransaction.commit()
        wantsAnimation = animated
        updateAnimations()
    }

    override func layout() { super.layout(); layoutArtwork() }
    private func layoutArtwork() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        movingLayer.frame = bounds
        for item in [bodyLayer, eyeLayer, whitesLayer, pupilContainer, pupilLayer, pupilMask] {
            // Preserve pupil translation while setting its untransformed bounds/position.
            item.bounds = CGRect(origin: .zero, size: bounds.size)
            item.position = CGPoint(x: bounds.width * item.anchorPoint.x, y: bounds.height * item.anchorPoint.y)
            item.contentsScale = window?.backingScaleFactor ?? 2
        }
        CATransaction.commit()
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateAnimations() }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layoutArtwork()
        updateAnimations()
    }

    private func updateAnimations() {
        guard wantsAnimation, window != nil else {
            movingLayer.removeAnimation(forKey: "bob")
            eyeLayer.removeAnimation(forKey: "blink")
            return
        }
        let frameRate = Float(window?.screen?.maximumFramesPerSecond ?? 60)
        guard movingLayer.animation(forKey: "bob") == nil || animationFrameRate != frameRate else { return }
        animationFrameRate = frameRate
        let range = CAFrameRateRange(minimum: min(60, frameRate), maximum: frameRate, preferred: frameRate)
        let time = Date().timeIntervalSinceReferenceDate
        let bob = CAKeyframeAnimation(keyPath: "transform.translation.y")
        bob.values = (0...240).map { sin(Double($0) / 240 * .pi * 2) * 2 }
        bob.duration = .pi * 2 / 1.5
        bob.timeOffset = time.truncatingRemainder(dividingBy: bob.duration)
        bob.repeatCount = .infinity
        bob.calculationMode = .linear
        bob.preferredFrameRateRange = range
        movingLayer.add(bob, forKey: "bob")
        let blink = CAKeyframeAnimation(keyPath: "transform.scale.y")
        blink.values = [1, 0.08, 0.08, 1, 1]
        blink.keyTimes = [0, NSNumber(value: 0.1012 / 5.7), NSNumber(value: 0.1188 / 5.7), NSNumber(value: 0.22 / 5.7), 1]
        blink.duration = 5.7
        blink.timeOffset = time.truncatingRemainder(dividingBy: blink.duration)
        blink.repeatCount = .infinity
        blink.calculationMode = .linear
        blink.preferredFrameRateRange = range
        eyeLayer.add(blink, forKey: "blink")
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
