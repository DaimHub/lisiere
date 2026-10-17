import SwiftUI

/// Tabs and toolbar customization move live on hover, using the same animation and drop lifecycle.
struct ReorderDropDelegate<ID: Equatable>: DropDelegate {
    let targetID: ID?
    @Binding var draggedID: ID?
    var canMove: (ID) -> Bool
    var move: (ID, ID) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedID, let targetID, draggedID != targetID, canMove(draggedID) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            move(draggedID, targetID)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info) else { return false }
        draggedID = nil
        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggedID.map(canMove) ?? false
    }
}
