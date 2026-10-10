//
//  BoardView.swift
//  moody
//

import SwiftData
import SwiftUI

struct BoardView: View {
    @Bindable var project: Project
    @Query private var items: [BoardItem]
    @State private var zoomScale: CGFloat = 1
    /// Board-space point under the cursor, kept up to date by hover so
    /// pinch-zoom is anchored at the cursor. nil until the mouse first moves
    /// over the board (zoom then anchors at the viewport center).
    @State private var zoomAnchor: CGPoint?
    @State private var canvasController = BoardCanvasController()

    init(project: Project) {
        _project = Bindable(project)
        let projectID = project.id
        _items = Query(
            filter: #Predicate<BoardItem> { $0.project?.id == projectID },
            sort: \BoardItem.zIndex
        )
    }

    var body: some View {
        BoardCanvasView(project: project, items: items, zoomScale: $zoomScale, zoomAnchor: $zoomAnchor, controller: canvasController)
            .navigationTitle(project.name)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Zoom to Fit", systemImage: "arrow.up.left.and.arrow.down.right") {
                        canvasController.zoomToFit()
                    }
                    .keyboardShortcut("0", modifiers: .command)
                    .help("Zoom to Fit (⌘0)")
                    .disabled(items.isEmpty)
                }
            }
    }
}
