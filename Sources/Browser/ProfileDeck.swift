import AppKit
import SwiftUI

@MainActor
protocol ProfileWorkspacePresenting: AnyObject {
    /// Returns false when the incoming workspace has not been rendered yet.
    @discardableResult func beginTransition(to profileID: UUID) -> Bool
}

private struct WorkspaceVisibilityManagedByHostKey: EnvironmentKey {
    static let defaultValue = false
}

struct WorkspaceSceneActions {
    let openWindow: OpenWindowAction
    let openSettings: OpenSettingsAction
}

private struct WorkspaceSceneActionsKey: EnvironmentKey {
    static let defaultValue: WorkspaceSceneActions? = nil
}

extension EnvironmentValues {
    var workspaceVisibilityManagedByHost: Bool {
        get { self[WorkspaceVisibilityManagedByHostKey.self] }
        set { self[WorkspaceVisibilityManagedByHostKey.self] = newValue }
    }
    var workspaceSceneActions: WorkspaceSceneActions? {
        get { self[WorkspaceSceneActionsKey.self] }
        set { self[WorkspaceSceneActionsKey.self] = newValue }
    }
}

struct ProfileDeckItem<Content: View> {
    let id: UUID
    let content: Content
}

/// One native stacking surface owns both cached workspaces. Warm profile switches can
/// commit their opacity animation before SwiftUI processes the changed model.
struct ProfileDeck<Content: View & Equatable>: NSViewRepresentable {
    let owner: ProfileWindowController
    let items: [ProfileDeckItem<Content>]
    let activeID: UUID?
    let animated: Bool
    @Environment(\.self) private var environment

    func makeNSView(context: Context) -> ProfileDeckView<ProfileDeckContent<Content>> {
        ProfileDeckView(frame: .zero)
    }

    func updateNSView(_ view: ProfileDeckView<ProfileDeckContent<Content>>, context: Context) {
        if view.owner !== owner {
            if view.owner?.workspacePresentation === view { view.owner?.workspacePresentation = nil }
            view.owner = owner
        }
        owner.workspacePresentation = view
        view.update(items: items.map {
            ProfileDeckItem(id: $0.id, content: ProfileDeckContent(content: $0.content, environment: environment))
        }, activeID: activeID, animated: animated)
    }

    func sizeThatFits(_ proposal: ProposedViewSize,
                      nsView: ProfileDeckView<ProfileDeckContent<Content>>,
                      context: Context) -> CGSize? {
        // Both cached workspaces fill the window's proposed viewport. They never determine
        // its intrinsic size; measuring their native subtrees repeats layout work needlessly.
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite else { return nil }
        return CGSize(width: width, height: height)
    }

    static func dismantleNSView(_ view: ProfileDeckView<ProfileDeckContent<Content>>, coordinator: ()) {
        if view.owner?.workspacePresentation === view { view.owner?.workspacePresentation = nil }
        view.releaseSurfaces()
    }
}

struct ProfileDeckContent<Content: View & Equatable>: View {
    let content: Content
    let environment: EnvironmentValues
    var body: some View {
        // Forward public scene actions and presentation preferences. Copying the entire
        // environment also copies SwiftUI's internal graph/accessibility context across roots.
        content.equatable()
            .environment(\.workspaceSceneActions,
                         WorkspaceSceneActions(openWindow: environment.openWindow, openSettings: environment.openSettings))
            .environment(\.scenePhase, environment.scenePhase)
            .environment(\.browserReduceMotion, environment.browserReduceMotion)
            .environment(\.colorScheme, environment.colorScheme)
            .environment(\.locale, environment.locale)
            .environment(\.calendar, environment.calendar)
            .environment(\.timeZone, environment.timeZone)
            .environment(\.layoutDirection, environment.layoutDirection)
            .environment(\.isEnabled, environment.isEnabled)
    }
}

final class ProfileDeckView<Content: View>: NSView, ProfileWorkspacePresenting {
    weak var owner: ProfileWindowController?
    private(set) var surfaces: [UUID: ProfileDeckSurface<Content>] = [:]
    private(set) var activeID: UUID?
    private var animationsEnabled = false
    private var hasPresentedWorkspace = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        for surface in surfaces.values where surface.frame != bounds { surface.frame = bounds }
    }

    func update(items: [ProfileDeckItem<Content>], activeID: UUID?, animated: Bool) {
        let retained = Set(items.map(\.id))
        for id in Array(surfaces.keys) where !retained.contains(id) {
            surfaces.removeValue(forKey: id)?.removeFromSuperview()
        }
        for item in items {
            if let surface = surfaces[item.id] {
                surface.update(content: item.content)
            } else {
                let surface = ProfileDeckSurface(content: item.content)
                surface.frame = bounds
                surface.autoresizingMask = [.width, .height]
                surfaces[item.id] = surface
                addSubview(surface)
            }
        }
        animationsEnabled = animated
        present(activeID, animated: animated && hasPresentedWorkspace)
        hasPresentedWorkspace = activeID != nil
    }

    @discardableResult
    func beginTransition(to profileID: UUID) -> Bool {
        guard window != nil, hasPresentedWorkspace, activeID != profileID,
              surfaces[profileID] != nil else { return false }
        present(profileID, animated: animationsEnabled)
        // Submit the cached surfaces now. The following model notifications can then
        // update SwiftUI while the render server advances the existing fade.
        CATransaction.flush()
        return true
    }

    private func present(_ id: UUID?, animated: Bool) {
        activeID = id
        for (profileID, surface) in surfaces {
            surface.setActive(profileID == id, animated: animated)
        }
    }

    func releaseSurfaces() {
        for surface in surfaces.values {
            surface.setActive(false, animated: false)
            surface.removeFromSuperview()
        }
        surfaces.removeAll()
        activeID = nil
        hasPresentedWorkspace = false
    }
}

/// Browser workspaces always contain their address field. AppKit queries this during
/// focus changes and titlebar-region updates; searching the full SwiftUI graph to
/// rediscover that field each time is unnecessary. SwiftUI still owns focus traversal.
private final class ProfileWorkspaceHostingView<Content: View>: NSHostingView<Content> {
    var workspaceActive = false
    override var acceptsFirstResponder: Bool { workspaceActive }
}

final class ProfileDeckSurface<Content: View>: NSView {
    private let hostingView: ProfileWorkspaceHostingView<Content>
    private let surface = NSView()
    private(set) var isActive = false
    private var initialized = false
    var opacityLayer: CALayer { surface.layer! }

    init(content: Content) {
        hostingView = ProfileWorkspaceHostingView(rootView: content)
        super.init(frame: .zero)
        wantsLayer = true
        surface.wantsLayer = true
        surface.frame = bounds
        surface.autoresizingMask = [.width, .height]
        hostingView.sizingOptions = []
        hostingView.frame = surface.bounds
        hostingView.autoresizingMask = [.width, .height]
        surface.addSubview(hostingView)
        addSubview(surface)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { isActive ? super.hitTest(point) : nil }
    func update(content: Content) { hostingView.rootView = content }

    func setActive(_ active: Bool, animated: Bool) {
        let changed = !initialized || active != isActive
        guard changed || (!animated && opacityLayer.animation(forKey: "profile-fade") != nil) else { return }
        let start = initialized ? (opacityLayer.presentation()?.opacity ?? opacityLayer.opacity) : 0
        let target: Float = active ? 1 : 0
        isActive = active
        hostingView.workspaceActive = active
        initialized = true
        setAccessibilityHidden(!active)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // These are owned native siblings, so ordering does not move live WebKit views.
        layer?.zPosition = active ? 1 : 0
        opacityLayer.removeAnimation(forKey: "profile-fade")
        opacityLayer.opacity = target
        if animated, start != target {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = start
            fade.toValue = target
            fade.duration = 0.22
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            let rate = Float(window?.screen?.maximumFramesPerSecond ?? NSScreen.main?.maximumFramesPerSecond ?? 60)
            fade.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
            opacityLayer.add(fade, forKey: "profile-fade")
        }
        CATransaction.commit()
    }
}
