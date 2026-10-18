import AppKit
import SwiftUI

/// Internal tab moves stay in this window. They do not depend on pasteboard metadata surviving an OS drag.
enum TabDropTarget: Equatable {
    case tab(UUID)
    case group(UUID?)
}

struct TabDropRegion: Equatable {
    var id: String
    var target: TabDropTarget
    var frame: CGRect
    var horizontal: Bool
    var viewport: String?
    var priority = 1

    var scrollID: AnyHashable {
        if case let .tab(id) = target { return AnyHashable(id) }
        return AnyHashable(id)
    }
}

struct TabDragFrames: Equatable {
    var regions: [TabDropRegion] = []
    var viewports: [String: CGRect] = [:]
    var horizontalViewports: Set<String> = []
}

struct TabDropSelection: Equatable {
    var region: TabDropRegion
    var after: Bool
}

struct TabDragScrollRequest: Equatable {
    var viewport: String
    var forward: Bool
    var horizontal: Bool
}

@MainActor @Observable
final class TabDragController {
    static let coordinateSpace = "browser-tab-strip-drag"
    private(set) var sourceID: UUID?
    private(set) var location: CGPoint?
    private(set) var selection: TabDropSelection?
    private(set) var scrollRequest: TabDragScrollRequest?
    @ObservationIgnored private var frames = TabDragFrames()
    @ObservationIgnored private var cancelled = false
    @ObservationIgnored private weak var origin: BrowserModel?
    @ObservationIgnored private var escapeMonitor: Any?

    func updateFrames(_ frames: TabDragFrames, browser: BrowserModel) {
        self.frames = frames
        if let sourceID, let location { update(id: sourceID, location: location, browser: browser) }
    }

    func update(id: UUID, location: CGPoint, browser: BrowserModel) {
        guard !cancelled, browser.tab(withID: id) != nil else { return }
        if sourceID == nil {
            sourceID = id
            origin = browser
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak browser] event in
                guard event.keyCode == 53, event.window === browser?.window else { return event }
                MainActor.assumeIsolated { self?.cancel() }
                return nil
            }
        }
        guard sourceID == id, origin === browser else { return }
        self.location = location
        selection = destination(at: location, sourceID: id, browser: browser)
        scrollRequest = scrolling(at: location)
    }

    /// Pick the most specific visible target first, then validate it. An invalid tab must not fall through
    /// to the ungrouped background, and clipped rows must not receive a drop in another scroll area.
    private func destination(at point: CGPoint, sourceID: UUID, browser: BrowserModel) -> TabDropSelection? {
        let region = frames.regions.filter { region in
            let visible = region.viewport.flatMap { frames.viewports[$0] }.map { region.frame.intersection($0) } ?? region.frame
            return visible.contains(point)
        }.max { a, b in
            if a.priority != b.priority { return a.priority < b.priority }
            return a.frame.width * a.frame.height > b.frame.width * b.frame.height
        }
        guard let region else { return nil }
        switch region.target {
        case let .tab(id): guard browser.canDropTab(sourceID, beside: id) else { return nil }
        case let .group(id): guard id == nil || browser.groups.contains(where: { $0.id == id }) else { return nil }
        }
        return TabDropSelection(region: region,
                                after: region.horizontal ? point.x > region.frame.midX : point.y > region.frame.midY)
    }

    func finish(id: UUID, location: CGPoint, browser: BrowserModel) {
        defer { reset() }
        guard !cancelled, origin === browser, sourceID == id else { return }
        update(id: id, location: location, browser: browser)
        guard let selection else { return }
        switch selection.region.target {
        case let .tab(target): browser.dropTab(id, beside: target, after: selection.after)
        case let .group(group): browser.dropTab(id, into: group)
        }
    }

    /// Ignore further movement until this gesture ends, including after Escape or a window switch.
    func cancel() {
        reset()
        cancelled = true
    }

    func reset() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        sourceID = nil
        location = nil
        selection = nil
        scrollRequest = nil
        origin = nil
        cancelled = false
    }

    private func scrolling(at point: CGPoint) -> TabDragScrollRequest? {
        for (id, frame) in frames.viewports where frame.contains(point) {
            let horizontal = frames.horizontalViewports.contains(id)
            let value = horizontal ? point.x : point.y
            let start = horizontal ? frame.minX : frame.minY
            let end = horizontal ? frame.maxX : frame.maxY
            let inset = min(20, (end - start) / 4)
            if value < start + inset { return .init(viewport: id, forward: false, horizontal: horizontal) }
            if value > end - inset { return .init(viewport: id, forward: true, horizontal: horizontal) }
        }
        return nil
    }

    func nextScrollTarget(_ request: TabDragScrollRequest) -> AnyHashable? {
        guard let viewport = frames.viewports[request.viewport] else { return nil }
        let edge = request.horizontal
            ? (request.forward ? viewport.maxX : viewport.minX)
            : (request.forward ? viewport.maxY : viewport.minY)
        let candidates = frames.regions.filter { $0.viewport == request.viewport && $0.priority > 0 }
        let next = candidates.filter { region in
            let value = request.horizontal
                ? (request.forward ? region.frame.maxX : region.frame.minX)
                : (request.forward ? region.frame.maxY : region.frame.minY)
            return request.forward ? value > edge + 1 : value < edge - 1
        }.min { a, b in
            let x = request.horizontal ? a.frame.midX : a.frame.midY
            let y = request.horizontal ? b.frame.midX : b.frame.midY
            return abs(x - edge) < abs(y - edge)
        }
        return next?.scrollID
    }
}

struct TabDropAnchor {
    var id: String
    var target: TabDropTarget
    var bounds: Anchor<CGRect>
    var horizontal: Bool
    var viewport: String?
    var priority: Int
}

struct TabDragBounds {
    var regions: [TabDropAnchor] = []
    var viewports: [String: Anchor<CGRect>] = [:]
    var horizontalViewports: Set<String> = []

    func resolve(in geometry: GeometryProxy) -> TabDragFrames {
        TabDragFrames(regions: regions.map {
            TabDropRegion(id: $0.id, target: $0.target, frame: geometry[$0.bounds], horizontal: $0.horizontal,
                          viewport: $0.viewport, priority: $0.priority)
        }, viewports: viewports.mapValues { geometry[$0] }, horizontalViewports: horizontalViewports)
    }
}

struct TabDragBoundsKey: PreferenceKey {
    static let defaultValue = TabDragBounds()
    static func reduce(value: inout TabDragBounds, nextValue: () -> TabDragBounds) {
        let next = nextValue()
        value.regions += next.regions
        value.viewports.merge(next.viewports) { $1 }
        value.horizontalViewports.formUnion(next.horizontalViewports)
    }
}

extension View {
    func tabDragViewport(_ id: String, horizontal: Bool) -> some View {
        transformAnchorPreference(key: TabDragBoundsKey.self, value: .bounds) { value, bounds in
            value.viewports[id] = bounds
            if horizontal { value.horizontalViewports.insert(id) }
        }
    }

    func tabDropRegion(_ id: String, target: TabDropTarget, horizontal: Bool, viewport: String? = nil,
                       priority: Int = 1, drag: TabDragController, accent: Color) -> some View {
        transformAnchorPreference(key: TabDragBoundsKey.self, value: .bounds) { value, bounds in
            value.regions.append(TabDropAnchor(id: id, target: target, bounds: bounds,
                                              horizontal: horizontal, viewport: viewport, priority: priority))
        }
        .overlay {
            if priority > 0, let selected = drag.selection, selected.region.id == id {
                switch target {
                case .group:
                    RoundedRectangle(cornerRadius: 7).strokeBorder(accent, lineWidth: 2).allowsHitTesting(false)
                case .tab:
                    Rectangle().fill(accent)
                        .frame(width: horizontal ? 2 : nil, height: horizontal ? nil : 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: horizontal ? (selected.after ? .trailing : .leading) : (selected.after ? .bottom : .top))
                        .allowsHitTesting(false)
                }
            }
        }
    }

    func tabDragAutoScroll(_ viewport: String, drag: TabDragController, proxy: ScrollViewProxy, reduceMotion: Bool) -> some View {
        task(id: drag.scrollRequest) {
            guard let request = drag.scrollRequest, request.viewport == viewport else { return }
            while !Task.isCancelled, drag.scrollRequest == request, let target = drag.nextScrollTarget(request) {
                withAnimation(reduceMotion ? nil : .linear(duration: 0.12)) {
                    proxy.scrollTo(target, anchor: request.horizontal
                                   ? (request.forward ? .trailing : .leading) : (request.forward ? .bottom : .top))
                }
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            }
        }
    }
}
