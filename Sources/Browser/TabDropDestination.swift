import SwiftUI
import UniformTypeIdentifiers

enum TabDragPayload {
    static let type = UTType(exportedAs: "io.github.daimhub.lisiere.tab", conformingTo: .data)

    static func provider(for id: UUID) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = id.uuidString
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { completion in
            completion(Data(id.uuidString.utf8), nil)
            return nil
        }
        return provider
    }

    static func id(from provider: NSItemProvider) -> UUID? {
        guard provider.hasItemConformingToTypeIdentifier(type.identifier), let name = provider.suggestedName else { return nil }
        return UUID(uuidString: name)
    }
}

enum TabDropTarget {
    case tab(UUID)
    case group(UUID?)
}

extension View {
    func tabDropDestination(browser: BrowserModel, target: TabDropTarget, horizontal: Bool, accent: Color) -> some View {
        modifier(TabDropModifier(browser: browser, target: target, horizontal: horizontal, accent: accent))
    }
}

private struct TabDropModifier: ViewModifier {
    let browser: BrowserModel
    let target: TabDropTarget
    let horizontal: Bool
    let accent: Color
    @State private var size: CGSize = .zero
    @State private var after: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .overlay {
                if let after {
                    switch target {
                    case .group:
                        RoundedRectangle(cornerRadius: 7).strokeBorder(accent, lineWidth: 2)
                            .allowsHitTesting(false)
                    case .tab:
                        Rectangle().fill(accent)
                            .frame(width: horizontal ? 2 : nil, height: horizontal ? nil : 2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity,
                                   alignment: horizontal ? (after ? .trailing : .leading) : (after ? .bottom : .top))
                            .allowsHitTesting(false)
                    }
                }
            }
            .onDrop(of: [TabDragPayload.type], delegate: TabDropDelegate(
                browser: browser, target: target, horizontal: horizontal, size: size,
                after: $after, reduceMotion: reduceMotion))
    }
}

/// Use the local provider itself, rather than view state that can be stale or recreated during a drag.
private struct TabDropDelegate: DropDelegate {
    let browser: BrowserModel
    let target: TabDropTarget
    let horizontal: Bool
    let size: CGSize
    @Binding var after: Bool?
    let reduceMotion: Bool

    private func source(in info: DropInfo) -> (NSItemProvider, UUID)? {
        guard let provider = info.itemProviders(for: [TabDragPayload.type]).first,
              let id = TabDragPayload.id(from: provider), browser.tabs.contains(where: { $0.id == id }) else { return nil }
        if case let .tab(targetID) = target, !browser.canDropTab(id, beside: targetID) { return nil }
        return (provider, id)
    }

    func validateDrop(info: DropInfo) -> Bool { source(in: info) != nil }

    func dropEntered(info: DropInfo) { updateIndicator(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateIndicator(info)
        return DropProposal(operation: validateDrop(info: info) ? .move : .forbidden)
    }

    private func updateIndicator(_ info: DropInfo) {
        after = validateDrop(info: info) ? isAfter(info.location) : nil
    }

    private func isAfter(_ point: CGPoint) -> Bool {
        horizontal ? point.x > size.width / 2 : point.y > size.height / 2
    }

    func dropExited(info: DropInfo) { after = nil }

    func performDrop(info: DropInfo) -> Bool {
        after = nil
        guard let (provider, id) = source(in: info) else { return false }
        let insertAfter = isAfter(info.location)
        provider.loadDataRepresentation(forTypeIdentifier: TabDragPayload.type.identifier) { data, _ in
            guard let data, String(data: data, encoding: .utf8) == id.uuidString else { return }
            Task { @MainActor in
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                    switch target {
                    case let .tab(targetID): browser.dropTab(id, beside: targetID, after: insertAfter)
                    case let .group(groupID): browser.dropTab(id, into: groupID)
                    }
                }
            }
        }
        return true
    }
}
