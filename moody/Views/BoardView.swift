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
    /// The document point (in BoardCanvasView's document-view coordinate
    /// space) that should stay fixed on screen as zoomScale changes — kept
    /// up to date with the mouse position so pinch-zoom is anchored at the
    /// cursor instead of always scaling from the board's top-left corner.
    @State private var zoomAnchor = CGPoint(
        x: BoardCanvasView.documentSize.width / 2,
        y: BoardCanvasView.documentSize.height / 2
    )

    init(project: Project) {
        self._project = Bindable(project)
        let projectID = project.id
        self._items = Query(
            filter: #Predicate<BoardItem> { $0.project?.id == projectID },
            sort: \BoardItem.zIndex
        )
    }

    var body: some View {
        BoardCanvasView(project: project, items: items, zoomScale: $zoomScale, zoomAnchor: $zoomAnchor)
            .navigationTitle(project.name)
    }
}
