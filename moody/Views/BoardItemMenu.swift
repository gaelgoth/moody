//
//  BoardItemMenu.swift
//  moody
//
//  Right-click actions on board items. The targets are the selection when the
//  clicked item is in it, otherwise the clicked item alone; each action first
//  makes them the selection, then runs BoardView's selection-based action.
//  Notes and containers append this inside their own .contextMenu (the
//  innermost menu wins, so an outer one would never show on them).
//

import SwiftUI

struct BoardItemMenuActions {
    var select: (Set<UUID>) -> Void
    /// Connects the two selected items, or unlinks them if they're linked.
    var connect: () -> Void
    var group: (StackAxis) -> Void
    var removeFromContainer: () -> Void
    var align: (BoardAlignment) -> Void
    var download: () -> Void
    /// Asks first when photos are involved (see BoardView.handleDeleteKey).
    var delete: () -> Void
}

struct BoardItemMenu: View {
    let targets: [BoardItem]
    let isLinked: Bool
    let actions: BoardItemMenuActions

    private var photoCount: Int {
        targets.count { $0.kind == .image }
    }

    var body: some View {
        if targets.count == 2 {
            button(isLinked ? "Unlink" : "Connect", systemImage: isLinked ? "scissors" : "link", action: actions.connect)
        }
        if photoCount > 0 {
            button("New Row Container", systemImage: "rectangle.split.3x1") { actions.group(.row) }
            button("New Column Container", systemImage: "rectangle.split.1x3") { actions.group(.column) }
        }
        if targets.contains(where: { $0.container != nil }) {
            button("Remove from Container", systemImage: "rectangle.portrait.and.arrow.right", action: actions.removeFromContainer)
        }
        if targets.count(where: { $0.container == nil }) >= 2 {
            Menu("Align") {
                ForEach(BoardAlignment.allCases, id: \.self) { alignment in
                    button(alignment.title, systemImage: alignment.systemImage) { actions.align(alignment) }
                }
            }
        }
        if photoCount > 0 {
            button(photoCount == 1 ? "Download Image" : "Download \(photoCount) Images", systemImage: "square.and.arrow.down",
                   action: actions.download)
        }
        Divider()
        button("Delete", systemImage: "trash", action: actions.delete)
    }

    private func button(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: systemImage) {
            actions.select(Set(targets.map(\.id)))
            action()
        }
    }
}
