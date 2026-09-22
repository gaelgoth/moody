//
//  BoardDocumentContentView.swift
//  moody
//
//  The fixed-size SwiftUI content hosted as an NSScrollView's documentView.
//  Laid out at a fixed LOGICAL size (documentSize) and visually scaled by
//  zoomScale via .scaleEffect — a SwiftUI-native transform, so drag
//  translations, hover tracking, and onDrop locations all stay correctly
//  aligned with what's on screen at any zoom level. (BoardCanvasView keeps
//  the hosting NSView's frame sized to documentSize * zoomScale so
//  NSScrollView's scroll bounds match the scaled rendering.)
//
//  Selection and drag state both live here, not on individual BoardItemViews:
//  a single drag gesture (recognized on whichever item is under the cursor)
//  needs to be able to move every OTHER selected item's rendered position
//  too, and the marquee-select rectangle needs to test against every item's
//  bounds. All SwiftData writes (position, and the bring-to-front zIndex
//  bump) happen only once a drag gesture ends, never mid-gesture: zIndex
//  feeds a @Query sort key, and mutating it while a drag is live can trigger
//  a re-render that reassigns the hosting NSHostingView's rootView, which
//  can intermittently kill the in-flight AppKit mouse tracking loop and
//  silently cancel the drag. Deferring writes to onEnded avoids that
//  entirely — see handleItemDragEnded/commitGroupMove.
//

import AppKit
import CoreGraphics
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BoardDocumentContentView: View {
    let project: Project
    let items: [BoardItem]
    let documentSize: CGSize
    @Binding var zoomScale: CGFloat
    @Binding var zoomAnchor: CGPoint

    @Environment(\.modelContext) private var modelContext

    /// The item a drag gesture is currently live on (tracked here, not
    /// written to the model, so the dragged item(s) render in front of their
    /// siblings instantly without a SwiftData write hitting the @Query
    /// mid-gesture — see file header).
    @State private var activeDragItemID: UUID?

    /// Live translation shared by every item in `movingItemIDs` — a group
    /// moves rigidly together, so one shared value is enough (no per-item map).
    @State private var dragTranslation: CGSize = .zero

    /// Ids of the currently multi-selected items. Ephemeral UI state, never
    /// persisted — resets whenever the board is reopened.
    @State private var selectedItemIDs: Set<UUID> = []

    /// The in-progress marquee (rubber-band) selection rectangle, in logical/
    /// document coordinates. nil when no marquee drag is in progress.
    @State private var marqueeRect: CGRect?

    /// Which item (if any) the cursor is currently over. Computed from a
    /// single continuous hover stream on this container rather than N
    /// independent per-item .onHover trackers — per-item hover exit proved
    /// unreliable on macOS once a .gesture() is also attached to the same
    /// view (the cursor could get stuck showing the open hand indefinitely
    /// after leaving an image). One source of truth avoids that entirely.
    @State private var hoveredItemID: UUID?

    /// The committed zoomScale value from just before the in-progress pinch
    /// gesture began, so each .onChanged tick can compute an absolute new
    /// zoomScale (MagnificationGesture's value is cumulative since gesture
    /// start, not incremental). Written directly into the shared zoomScale
    /// binding on every tick — not tracked separately via @GestureState —
    /// so BoardCanvasView (which resizes the NSScrollView's hosting frame
    /// off the same zoomScale) stays in sync for the whole gesture, not
    /// just once it ends. A split "live vs. committed" value was exactly
    /// the bug: BoardCanvasView only saw the committed one, so the content
    /// and the scroll frame disagreed on scale for the entire pinch.
    @State private var gestureBaseScale: CGFloat?

    private static let minZoom: CGFloat = 0.1
    private static let maxZoom: CGFloat = 4

    /// Ids of items the live drag should move: the whole selection if the
    /// dragged item is a member of a multi-item selection, otherwise just
    /// the dragged item alone.
    private var movingItemIDs: Set<UUID> {
        itemsToMove(draggedID: activeDragItemID, selection: selectedItemIDs)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(marqueeGesture)

            ForEach(items.sorted(by: { $0.zIndex < $1.zIndex })) { item in
                BoardItemView(
                    item: item,
                    isSelected: selectedItemIDs.contains(item.id),
                    liveTranslation: movingItemIDs.contains(item.id) ? dragTranslation : .zero,
                    onDragChanged: { translation in
                        handleItemDragChanged(itemID: item.id, translation: translation)
                    },
                    onDragEnded: { translation in
                        handleItemDragEnded(translation: translation)
                    }
                )
                .zIndex(movingItemIDs.contains(item.id) ? .infinity : Double(item.zIndex))
            }

            if let marqueeRect {
                marqueeOverlay(marqueeRect)
                    .zIndex(.greatestFiniteMagnitude)
            }
        }
        .frame(width: documentSize.width, height: documentSize.height)
        .scaleEffect(zoomScale, anchor: .topLeading)
        // .scaleEffect renders bigger but does NOT change the reported
        // layout size (it stays documentSize) — without this outer frame,
        // SwiftUI would position the nominally-20000x20000 content inside
        // whatever larger size BoardCanvasView gives the hosting NSView,
        // instead of filling it from the top-left, so on-screen items would
        // land somewhere other than where onDrop/onContinuousHover (and the
        // NSScrollView's own scroll bounds) expect them to be.
        .frame(
            width: documentSize.width * zoomScale,
            height: documentSize.height * zoomScale,
            alignment: .topLeading
        )
        .contentShape(Rectangle())
        .gesture(magnificationGesture)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                zoomAnchor = point
                hoveredItemID = topmostItem(at: logicalPoint(from: point))?.id
            case .ended:
                hoveredItemID = nil
            }
            updateCursor()
        }
        .onDrop(of: [UTType.image], isTargeted: nil) { providers, location in
            let dropPoint = logicalPoint(from: location)
            Task {
                await ImageImportService.importDroppedItems(providers, into: project, at: dropPoint, context: modelContext)
            }
            return true
        }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let base = gestureBaseScale ?? zoomScale
                if gestureBaseScale == nil {
                    gestureBaseScale = base
                }
                zoomScale = min(max(base * value, Self.minZoom), Self.maxZoom)
            }
            .onEnded { _ in
                gestureBaseScale = nil
            }
    }

    /// Attached to a child INSIDE the ZStack's .scaleEffect (unlike
    /// magnification/hover/drop above, which are attached to the outer,
    /// post-scale container) — so value.location/.startLocation already
    /// arrive in logical/document coordinates. Do NOT run these through
    /// logicalPoint(from:), which is calibrated for the outer view space;
    /// reusing it here would silently double-convert, only visibly wrong at
    /// zoom levels other than 1.0.
    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let rect = CGRect(
                    x: min(value.startLocation.x, value.location.x),
                    y: min(value.startLocation.y, value.location.y),
                    width: abs(value.location.x - value.startLocation.x),
                    height: abs(value.location.y - value.startLocation.y)
                )
                marqueeRect = rect
                selectedItemIDs = itemsIntersecting(rect, items: items.map {
                    (id: $0.id, center: CGPoint(x: $0.positionX, y: $0.positionY),
                     size: CGSize(width: $0.width, height: $0.height))
                })
                updateCursor()
            }
            .onEnded { _ in
                marqueeRect = nil
                updateCursor()
            }
    }

    @ViewBuilder
    private func marqueeOverlay(_ rect: CGRect) -> some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.12))
            .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    private func handleItemDragChanged(itemID: UUID, translation: CGSize) {
        if activeDragItemID == nil {
            activeDragItemID = itemID
            if !selectedItemIDs.contains(itemID) {
                selectedItemIDs = [itemID]
            }
        }
        dragTranslation = translation
        updateCursor()
    }

    private func handleItemDragEnded(translation: CGSize) {
        // A plain click (no movement) always makes the clicked item the sole
        // selection, even if it was already part of a larger group — otherwise
        // clicking one member of a selection would silently re-stack and
        // re-save the whole group instead of just the clicked item.
        if translation == .zero, let clicked = activeDragItemID {
            selectedItemIDs = [clicked]
        }
        let movingItems = items.filter { movingItemIDs.contains($0.id) }
        commitGroupMove(movingItems: movingItems, allZIndices: items.map(\.zIndex), translation: translation)
        try? modelContext.save()
        activeDragItemID = nil
        dragTranslation = .zero
        updateCursor()
    }

    /// onContinuousHover/onDrop report points in this view's own (post
    /// .scaleEffect + outer .frame) layout space, which now spans
    /// documentSize * zoomScale — divide back down to the logical/
    /// document units that item.positionX/Y are stored in.
    private func logicalPoint(from visualPoint: CGPoint) -> CGPoint {
        CGPoint(x: visualPoint.x / zoomScale, y: visualPoint.y / zoomScale)
    }

    private func topmostItem(at point: CGPoint) -> BoardItem? {
        items
            .filter { item in
                let rect = CGRect(
                    x: item.positionX - item.width / 2,
                    y: item.positionY - item.height / 2,
                    width: item.width,
                    height: item.height
                )
                return rect.contains(point)
            }
            .max(by: { $0.zIndex < $1.zIndex })
    }

    private func updateCursor() {
        if activeDragItemID != nil {
            NSCursor.closedHand.set()
        } else if marqueeRect != nil {
            NSCursor.arrow.set()
        } else if hoveredItemID != nil {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}
