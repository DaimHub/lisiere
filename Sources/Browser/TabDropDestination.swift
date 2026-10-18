import AppKit
import SwiftUI

/// Internal tab moves stay in this window. They do not depend on pasteboard metadata surviving an OS drag.
enum TabDropTarget: Equatable {
    case tab(UUID)
    case group(UUID?)
    case groupOrder(UUID)
}

private enum TabDragSource: Equatable {
    case tab(UUID)
    case group(UUID)
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

    var indicator: TabDropIndicator {
        // Header drops have no before/after distinction. Their animated midpoint must not
        // invalidate every header and card while the pointer stays in the same folder.
        let showsInsertion: Bool
        if case .group = region.target { showsInsertion = false } else { showsInsertion = true }
        return TabDropIndicator(id: region.id, target: region.target, after: showsInsertion && after)
    }
}

/// Visual state excludes the continuously moving bounds used by hit testing.
struct TabDropIndicator: Equatable {
    var id: String
    var target: TabDropTarget
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
    private var source: TabDragSource?
    var sourceID: UUID? {
        if case let .tab(id) = source { return id }
        return nil
    }
    var sourceGroupID: UUID? {
        if case let .group(id) = source { return id }
        return nil
    }
    var isDragging: Bool { source != nil }
    private(set) var location: CGPoint?
    @ObservationIgnored private(set) var selection: TabDropSelection?
    private(set) var indicator: TabDropIndicator?
    private(set) var scrollRequest: TabDragScrollRequest?
    @ObservationIgnored private var frames = TabDragFrames()
    @ObservationIgnored private var cancelled = false
    @ObservationIgnored private weak var origin: BrowserModel?
    @ObservationIgnored private var escapeMonitor: Any?
    @ObservationIgnored private var hoveredGroupID: UUID?
    @ObservationIgnored private var groupExpansionTask: Task<Void, Never>?
    @ObservationIgnored private var springLoadedGroupID: UUID?
    @ObservationIgnored private var groupCollapseTask: Task<Void, Never>?

    func updateFrames(_ frames: TabDragFrames, browser: BrowserModel) {
        self.frames = frames
        if let source, let location { update(source: source, location: location, browser: browser) }
    }

    func update(id: UUID, location: CGPoint, browser: BrowserModel) {
        update(source: .tab(id), location: location, browser: browser)
    }

    func updateGroup(id: UUID, location: CGPoint, browser: BrowserModel) {
        update(source: .group(id), location: location, browser: browser)
    }

    private func update(source: TabDragSource, location: CGPoint, browser: BrowserModel) {
        guard !cancelled else { return }
        switch source {
        case let .tab(id): guard browser.tab(withID: id) != nil else { return }
        case let .group(id): guard browser.groups.contains(where: { $0.id == id }) else { return }
        }
        if self.source == nil {
            self.source = source
            origin = browser
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak browser] event in
                guard event.keyCode == 53, event.window === browser?.window else { return event }
                MainActor.assumeIsolated { self?.cancel() }
                return nil
            }
        }
        guard self.source == source, origin === browser else { return }
        if self.location != location { self.location = location }
        scheduleGroupCollapse(browser: browser)
        selection = destination(at: location, source: source, browser: browser)
        let indicator = selection?.indicator
        if self.indicator != indicator { self.indicator = indicator }
        let scrollRequest = scrolling(at: location)
        if self.scrollRequest != scrollRequest { self.scrollRequest = scrollRequest }
        scheduleGroupExpansion(browser: browser)
    }

    /// Spring-load a collapsed folder after a deliberate hover. Movement inside the same header
    /// keeps the deadline; leaving, scrolling it away or ending the gesture cancels the pending work.
    private func scheduleGroupExpansion(browser: BrowserModel) {
        let groupID: UUID?
        if sourceID != nil, case let .group(id?) = selection?.region.target,
           browser.groups.contains(where: { $0.id == id && $0.isCollapsed }) {
            groupID = id
        } else {
            groupID = nil
        }
        guard groupID != hoveredGroupID else { return }
        cancelGroupExpansion()
        guard let groupID, let tabID = sourceID else { return }
        hoveredGroupID = groupID
        groupExpansionTask = Task { [weak self, weak browser] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard !Task.isCancelled, let self, let browser, self.hoveredGroupID == groupID else { return }
            self.hoveredGroupID = nil
            self.groupExpansionTask = nil
            guard self.origin === browser, self.sourceID == tabID, browser.tab(withID: tabID) != nil,
                  let point = self.location,
                  self.destination(at: point, source: .tab(tabID), browser: browser)?.region.target == .group(groupID),
                  browser.groups.contains(where: { $0.id == groupID && $0.isCollapsed })
            else { return }
            // Restore any previous folder before transferring ownership to this one.
            self.restoreSpringLoadedGroup()
            self.springLoadedGroupID = groupID
            browser.expandGroup(groupID)
        }
    }

    private func cancelGroupExpansion() {
        groupExpansionTask?.cancel()
        groupExpansionTask = nil
        hoveredGroupID = nil
    }

    /// Allow a brief excursion outside an auto-opened folder. Re-entry cancels the close;
    /// movement and geometry updates outside keep the original deadline.
    private func scheduleGroupCollapse(browser: BrowserModel) {
        guard let groupID = springLoadedGroupID, let point = location,
              !contains(point, inGroup: groupID, browser: browser) else {
            cancelGroupCollapse()
            return
        }
        guard groupCollapseTask == nil else { return }
        groupCollapseTask = Task { [weak self, weak browser] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard !Task.isCancelled, let self, let browser else { return }
            self.groupCollapseTask = nil
            guard self.origin === browser, self.springLoadedGroupID == groupID,
                  self.sourceID != nil, let point = self.location,
                  !self.contains(point, inGroup: groupID, browser: browser) else { return }
            self.restoreSpringLoadedGroup()
        }
    }

    private func cancelGroupCollapse() {
        groupCollapseTask?.cancel()
        groupCollapseTask = nil
    }

    private func visibleFrame(of region: TabDropRegion) -> CGRect {
        region.viewport.flatMap { frames.viewports[$0] }.map { region.frame.intersection($0) } ?? region.frame
    }

    /// Keep the folder open across its header, child cards and internal gaps, even over an invalid
    /// insertion target (for example, a pinned site over an ordinary child). Clipped content is outside.
    private func contains(_ point: CGPoint, inGroup groupID: UUID, browser: BrowserModel) -> Bool {
        frames.regions.contains { region in
            guard visibleFrame(of: region).contains(point) else { return false }
            switch region.target {
            case let .group(id): return id == groupID
            case let .groupOrder(id): return id == groupID
            case let .tab(id): return browser.tab(withID: id)?.groupID == groupID
            }
        }
    }

    private func restoreSpringLoadedGroup() {
        cancelGroupCollapse()
        guard let groupID = springLoadedGroupID else { return }
        springLoadedGroupID = nil
        origin?.collapseGroup(groupID)
    }

    private func keepSpringLoadedGroup(afterDropping tabID: UUID, into groupID: UUID?, browser: BrowserModel) {
        guard let groupID, groupID == springLoadedGroupID, browser.tab(withID: tabID)?.groupID == groupID else { return }
        cancelGroupCollapse()
        springLoadedGroupID = nil
    }

    /// Pick the most specific visible target first, then validate it. An invalid tab must not fall through
    /// to the ungrouped background, and clipped rows must not receive a drop in another scroll area.
    private func destination(at point: CGPoint, source: TabDragSource, browser: BrowserModel) -> TabDropSelection? {
        let region = frames.regions.lazy.filter { region in
            // Keep occupied regions as blockers so a folder cannot fall through a loose tab to the background.
            switch (source, region.target) {
            case (.group, _), (.tab, .tab), (.tab, .group): break
            default: return false
            }
            return self.visibleFrame(of: region).contains(point)
        }.max { a, b in
            if case .group = source {
                // A folder section owns its children while reordering whole folders.
                switch (a.target, b.target) {
                case (.groupOrder, .groupOrder): break
                case (.groupOrder, _): return false
                case (_, .groupOrder): return true
                default: break
                }
            }
            if a.priority != b.priority { return a.priority < b.priority }
            return a.frame.width * a.frame.height > b.frame.width * b.frame.height
        }
        guard let region else { return nil }
        switch (source, region.target) {
        case let (.tab(sourceID), .tab(id)):
            // SwiftUI can retain an outgoing card's anchor during its collapse transition.
            // Keep it a blocker until its frame disappears, but never drop into the hidden child.
            guard browser.canDropTab(sourceID, beside: id), let tab = browser.tab(withID: id),
                  !browser.groups.contains(where: { $0.id == tab.groupID && $0.isCollapsed }) else { return nil }
        case let (.tab, .group(id)):
            guard id == nil || browser.groups.contains(where: { $0.id == id }) else { return nil }
        case let (.group(sourceID), .groupOrder(id)):
            guard sourceID != id, browser.groups.contains(where: { $0.id == id }) else { return nil }
        case (.group, .group(nil)): break
        default: return nil
        }
        return TabDropSelection(region: region,
                                after: region.horizontal ? point.x > region.frame.midX : point.y > region.frame.midY)
    }

    func finish(id: UUID, location: CGPoint, browser: BrowserModel) {
        finish(source: .tab(id), location: location, browser: browser)
    }

    func finishGroup(id: UUID, location: CGPoint, browser: BrowserModel) {
        finish(source: .group(id), location: location, browser: browser)
    }

    private func finish(source: TabDragSource, location: CGPoint, browser: BrowserModel) {
        defer { reset() }
        guard !cancelled, origin === browser, self.source == source else { return }
        update(source: source, location: location, browser: browser)
        guard let selection else { return }
        switch (source, selection.region.target) {
        case let (.tab(id), .tab(target)):
            browser.dropTab(id, beside: target, after: selection.after)
            keepSpringLoadedGroup(afterDropping: id, into: browser.tab(withID: target)?.groupID, browser: browser)
        case let (.tab(id), .group(group)):
            browser.dropTab(id, into: group)
            keepSpringLoadedGroup(afterDropping: id, into: group, browser: browser)
        case let (.group(id), .groupOrder(target)): browser.moveGroup(id, beside: target, after: selection.after)
        case let (.group(id), .group(nil)): browser.moveGroupToEnd(id)
        default: break
        }
    }

    /// Ignore further movement until this gesture ends, including after Escape or a window switch.
    func cancel() {
        reset()
        cancelled = true
    }

    func reset() {
        cancelGroupExpansion()
        restoreSpringLoadedGroup()
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        source = nil
        location = nil
        selection = nil
        indicator = nil
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
        let candidates = frames.regions.filter {
            if case .groupOrder = $0.target { return false }
            return $0.viewport == request.viewport && $0.priority > 0
        }
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
            if priority > 0, let selected = drag.indicator, selected.id == id {
                switch target {
                case .group:
                    RoundedRectangle(cornerRadius: 7).strokeBorder(accent, lineWidth: 2).allowsHitTesting(false)
                case .tab, .groupOrder:
                    Rectangle().fill(accent)
                        .frame(width: horizontal ? 2 : nil, height: horizontal ? nil : 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: horizontal ? (selected.after ? .trailing : .leading) : (selected.after ? .bottom : .top))
                        .allowsHitTesting(false)
                }
            }
        }
    }

    @ViewBuilder
    func tabGroupDropRegion(_ sectionID: String, groupID: UUID?, horizontal: Bool, viewport: String,
                            drag: TabDragController, accent: Color) -> some View {
        if let groupID {
            self.opacity(drag.sourceGroupID == groupID ? 0.4 : 1)
                .tabDropRegion("group-order-" + sectionID, target: .groupOrder(groupID), horizontal: horizontal,
                               viewport: viewport, drag: drag, accent: accent)
        } else {
            self
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
