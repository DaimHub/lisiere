import AppKit

/// A one-shot scene handoff. The source retains the tab until the new window is connected.
@MainActor
final class TabWindowTransfer {
    private static var pending: [UUID: TabWindowTransfer] = [:]
    let source: BrowserModel
    let tabID: UUID
    let screenPoint: CGPoint

    private init(source: BrowserModel, tabID: UUID, screenPoint: CGPoint) {
        self.source = source
        self.tabID = tabID
        self.screenPoint = screenPoint
    }

    static func prepare(tabID: UUID, source: BrowserModel, at screenPoint: CGPoint) -> UUID? {
        guard source.isActiveInWorkspace, source.tab(withID: tabID)?.canMoveBetweenWindows == true else { return nil }
        let id = UUID()
        pending[id] = TabWindowTransfer(source: source, tabID: tabID, screenPoint: screenPoint)
        // If scene creation fails, leave the page where it was and release the request.
        Task {
            try? await Task.sleep(for: .seconds(10))
            pending.removeValue(forKey: id)
        }
        return id
    }

    static func take(_ id: UUID?, profileID: UUID, isPrivate: Bool) -> TabWindowTransfer? {
        guard let id, let transfer = pending[id], transfer.source.isPrivate == isPrivate,
              isPrivate || transfer.source.profileID == profileID else { return nil }
        pending.removeValue(forKey: id)
        guard transfer.source.isActiveInWorkspace,
              transfer.source.tab(withID: transfer.tabID)?.canMoveBetweenWindows == true else { return nil }
        return transfer
    }

    static func frame(for size: CGSize, at point: CGPoint, screens: [CGRect]) -> CGRect {
        let screen = screens.first { $0.contains(point) } ?? screens.min {
            hypot($0.midX - point.x, $0.midY - point.y) < hypot($1.midX - point.x, $1.midY - point.y)
        }
        guard let screen else { return CGRect(origin: point, size: size) }
        let width = min(size.width, screen.width), height = min(size.height, screen.height)
        return CGRect(x: min(max(point.x - min(160, width / 2), screen.minX), screen.maxX - width),
                      y: min(max(point.y - height + 20, screen.minY), screen.maxY - height),
                      width: width, height: height)
    }
}
