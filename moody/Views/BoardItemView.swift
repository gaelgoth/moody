//
//  BoardItemView.swift
//  moody
//
//  One placed image on a board: renders at its stored position/size, and
//  reports drag gestures up to BoardDocumentContentView, which owns
//  selection state and commits the resulting move(s) to the model — see
//  that file for why model writes must happen only once a drag ends, never
//  mid-gesture.
//
//  Cursor feedback (open/closed hand) is NOT handled here — it's centralized
//  in BoardDocumentContentView via a single continuous hover tracker, since
//  per-item .onHover proved unreliable on macOS once a .gesture() is also
//  attached to the same view (hover-exit could be missed, leaving the
//  cursor stuck).
//

import SwiftUI

struct BoardItemView: View {
    let item: BoardItem
    let isSelected: Bool
    /// Offset applied to this item's rendered position while it (or its
    /// selection group) is being dragged. Owned by the parent, not local
    /// state, so one gesture recognized on one item can move every selected
    /// sibling in lockstep.
    let liveTranslation: CGSize
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize) -> Void

    @State private var image: NSImage?

    var body: some View {
        content
            .frame(width: item.width, height: item.height)
            .overlay(selectionOverlay)
            .contentShape(Rectangle())
            .position(x: item.positionX + liveTranslation.width, y: item.positionY + liveTranslation.height)
            .gesture(dragGesture)
            .task(id: item.fileName) {
                image = ImageCache.shared.image(for: item)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .shadow(radius: 4)
        } else {
            Rectangle().fill(Color.gray.opacity(0.15))
        }
    }

    @ViewBuilder
    private var selectionOverlay: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: 3)
        }
    }

    private var dragGesture: some Gesture {
        // minimumDistance: 0 so a plain click (no movement) also fires
        // onChanged/onEnded with a zero translation — that's what makes a
        // click-without-drag select just this item (see
        // BoardDocumentContentView.handleItemDragChanged).
        DragGesture(minimumDistance: 0)
            .onChanged { value in onDragChanged(value.translation) }
            .onEnded { value in onDragEnded(value.translation) }
    }
}
