//
//  BoardDocumentContentView.swift
//  moody
//
//  The SwiftUI content hosted as an NSScrollView's documentView. Laid out at
//  extent.size, with board coordinates shifted by -extent.origin (the extent
//  is decided by BoardCanvasView), and visually scaled by zoomScale via
//  .scaleEffect — a SwiftUI-native transform, so drag
//  translations, hover tracking, and onDrop locations all stay correctly
//  aligned with what's on screen at any zoom level. (BoardCanvasView keeps
//  the hosting NSView's frame sized to extent.size * zoomScale so
//  NSScrollView's scroll bounds match the scaled rendering.)
//
//  Drag state lives here, and selection is edited here (BoardView owns it so
//  its toolbar can act on it), not on individual BoardItemViews:
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
    let connectors: [BoardConnector]
    /// Board-space rect this view renders, decided by BoardCanvasView; its
    /// origin maps to this view's (0, 0).
    let extent: CGRect
    @Binding var zoomScale: CGFloat
    /// Board-space point under the cursor (see BoardView).
    @Binding var zoomAnchor: CGPoint?
    /// Ids of the currently selected items. Owned by BoardView (its toolbar
    /// acts on the selection); ephemeral, never persisted.
    @Binding var selectedItemIDs: Set<UUID>
    /// See BoardView. Typing writes the model live; endEditing() saves.
    @Binding var editingItemID: UUID?
    /// The clicked connector line (see BoardView); cleared when items are selected.
    @Binding var selectedConnectorID: UUID?

    @Environment(\.modelContext) private var modelContext

    /// The item a drag gesture is currently live on (tracked here, not
    /// written to the model, so the dragged item(s) render in front of their
    /// siblings instantly without a SwiftData write hitting the @Query
    /// mid-gesture — see file header).
    @State private var activeDragItemID: UUID?

    /// Live translation shared by every item in `movingItemIDs` — a group
    /// moves rigidly together, so one shared value is enough (no per-item map).
    @State private var dragTranslation: CGSize = .zero

    /// The in-progress marquee (rubber-band) selection rectangle, in board
    /// coordinates. nil when no marquee drag is in progress.
    @State private var marqueeRect: CGRect?

    /// The container a release right now would stack the dragged photos into
    /// (highlighted). Live drag state like dragTranslation: never persisted.
    @State private var dropTargetContainerID: UUID?

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

    /// Ids of items the live drag should move: the whole selection if the
    /// dragged item is a member of a multi-item selection, otherwise just the
    /// dragged item, plus the stacked photos of any container among them.
    private var movingItemIDs: Set<UUID> {
        expandingContainers(itemsToMove(draggedID: activeDragItemID, selection: selectedItemIDs), children: stackChildren)
    }

    /// Container id → ids of the photos stacked in it.
    private var stackChildren: [UUID: [UUID]] {
        items.reduce(into: [:]) { map, item in
            if let containerID = item.container?.id {
                map[containerID, default: []].append(item.id)
            }
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            let moving = movingItemIDs
            BoardBackgroundView(extent: extent, showsGrid: project.showsGrid, isDark: project.usesDarkBackground)
                .contentShape(Rectangle())
                .gesture(marqueeGesture)

            ConnectorLayerView(
                connectors: connectors,
                extentOrigin: extent.origin,
                isDarkBoard: project.usesDarkBackground,
                selectedConnectorID: selectedConnectorID,
                liveRect: { liveRect(of: $0, moving: moving) },
                onSelect: { id in
                    endEditing()
                    selectedItemIDs = []
                    selectedConnectorID = id
                },
                onUnlink: unlink
            )
            // Above the background (0), below every item (zIndex ≥ 1 via nextZIndex).
            .zIndex(0.5)

            ForEach(items.sorted(by: { $0.zIndex < $1.zIndex })) { item in
                BoardItemView(
                    item: item,
                    canvasOrigin: extent.origin,
                    isSelected: selectedItemIDs.contains(item.id),
                    isEditing: editingItemID == item.id,
                    isDropTarget: dropTargetContainerID == item.id,
                    liveTranslation: moving.contains(item.id) ? dragTranslation : .zero,
                    onDragChanged: { translation in
                        handleItemDragChanged(itemID: item.id, translation: translation)
                    },
                    onDragEnded: { translation in
                        handleItemDragEnded(translation: translation)
                    },
                    onEndEditing: endEditing
                )
                .zIndex(moving.contains(item.id) ? .infinity : Double(item.zIndex))
            }

            if let marqueeRect {
                marqueeOverlay(marqueeRect)
                    .zIndex(.greatestFiniteMagnitude)
            }
        }
        // Container headers and hints follow the board's background, not the system appearance.
        .environment(\.colorScheme, project.usesDarkBackground ? .dark : .light)
        .frame(width: extent.width, height: extent.height)
        .scaleEffect(zoomScale, anchor: .topLeading)
        // .scaleEffect renders bigger but does NOT change the reported
        // layout size (it stays extent.size) — without this outer frame,
        // SwiftUI would position the unscaled-size content inside
        // whatever larger size BoardCanvasView gives the hosting NSView,
        // instead of filling it from the top-left, so on-screen items would
        // land somewhere other than where onDrop/onContinuousHover (and the
        // NSScrollView's own scroll bounds) expect them to be.
        .frame(
            width: extent.width * zoomScale,
            height: extent.height * zoomScale,
            alignment: .topLeading
        )
        .contentShape(Rectangle())
        .gesture(magnificationGesture)
        .onContinuousHover { phase in
            switch phase {
            case let .active(point):
                let boardPoint = logicalPoint(from: point)
                zoomAnchor = boardPoint
                hoveredItemID = topmostItem(at: boardPoint)?.id
            case .ended:
                hoveredItemID = nil
            }
            updateCursor()
        }
        .onDrop(of: [UTType.image], isTargeted: nil) { providers, location in
            let dropPoint = logicalPoint(from: location)
            let containers = items.filter { $0.kind == .container }
            let targetID = topmostContaining(dropPoint, items: containers.map { (id: $0.id, center: $0.center, size: $0.size) })
            let target = containers.first { $0.id == targetID }
            Task {
                await ImageImportService.importDroppedItems(
                    providers, into: project, at: dropPoint, container: target, context: modelContext
                )
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
                zoomScale = min(max(base * value, BoardZoom.minScale), BoardZoom.maxScale)
            }
            .onEnded { _ in
                gestureBaseScale = nil
            }
    }

    /// Attached to a child INSIDE the ZStack's .scaleEffect (unlike
    /// magnification/hover/drop above, which are attached to the outer,
    /// post-scale container) — so value.location/.startLocation already
    /// arrive in this ZStack's unscaled local space, which is board space
    /// minus extent.origin: add the origin back, but do NOT run these through
    /// logicalPoint(from:), which is calibrated for the outer view space;
    /// reusing it here would silently double-convert, only visibly wrong at
    /// zoom levels other than 1.0.
    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                endEditing()
                selectedConnectorID = nil
                let start = CGPoint(x: value.startLocation.x + extent.minX, y: value.startLocation.y + extent.minY)
                let end = CGPoint(x: value.location.x + extent.minX, y: value.location.y + extent.minY)
                let rect = CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
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

    private func marqueeOverlay(_ rect: CGRect) -> some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.12))
            .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX - extent.minX, y: rect.midY - extent.minY)
            .allowsHitTesting(false)
    }

    private func handleItemDragChanged(itemID: UUID, translation: CGSize) {
        if activeDragItemID == nil {
            selectedConnectorID = nil
            if editingItemID != itemID {
                endEditing()
            }
            activeDragItemID = itemID
            if !selectedItemIDs.contains(itemID) {
                selectedItemIDs = [itemID]
            }
        }
        dragTranslation = translation
        dropTargetContainerID = stackDropTarget(translation: translation)
        updateCursor()
    }

    private func handleItemDragEnded(translation: CGSize) {
        // A plain click (no movement) always makes the clicked item the sole
        // selection, even if it was already part of a larger group — otherwise
        // clicking one member of a selection would silently re-stack and
        // re-save the whole group instead of just the clicked item.
        if translation == .zero, let clicked = activeDragItemID {
            selectedItemIDs = [clicked]
            // The item's only gesture is this zero-distance drag, so a
            // double-click is read from the event instead of a competing
            // TapGesture(count: 2) that would delay single-click selection.
            if NSApp.currentEvent?.clickCount == 2, items.first(where: { $0.id == clicked })?.kind != .image {
                editingItemID = clicked
            }
        }
        let movingItems = items.filter { movingItemIDs.contains($0.id) }
        let target = dropTargetContainerID.flatMap { id in items.first { $0.id == id } }
        let dragged = items.first { $0.id == activeDragItemID }
        let allZIndices = items.map(\.zIndex)
        commitGroupMove(movingItems: movingItems, allZIndices: allZIndices, translation: translation)
        // A click (no movement) never changes stack membership or order.
        if translation != .zero {
            commitStackDrop(movingItems: movingItems, target: target, dragged: dragged, allZIndices: allZIndices)
        }
        try? modelContext.save()
        activeDragItemID = nil
        dragTranslation = .zero
        dropTargetContainerID = nil
        updateCursor()
    }

    /// The front-most container under the dragged item's live center that a
    /// release would stack into. Only photos stack, and a drag that carries a
    /// container never targets one.
    private func stackDropTarget(translation: CGSize) -> UUID? {
        let moving = movingItemIDs
        let movingItems = items.filter { moving.contains($0.id) }
        guard movingItems.contains(where: { $0.kind == .image }),
              !movingItems.contains(where: { $0.kind == .container }),
              let dragged = items.first(where: { $0.id == activeDragItemID })
        else { return nil }
        let probe = CGPoint(x: dragged.positionX + translation.width, y: dragged.positionY + translation.height)
        // items comes from the @Query sorted by zIndex, i.e. back to front.
        let containers = items.filter { $0.kind == .container && !moving.contains($0.id) }
        return topmostContaining(probe, items: containers.map { (id: $0.id, center: $0.center, size: $0.size) })
    }

    private func liveRect(of item: BoardItem, moving: Set<UUID>) -> CGRect {
        let offset = moving.contains(item.id) ? dragTranslation : .zero
        return CGRect(
            x: item.positionX - item.width / 2 + offset.width,
            y: item.positionY - item.height / 2 + offset.height,
            width: item.width,
            height: item.height
        )
    }

    /// Context-menu click, never mid-gesture.
    private func unlink(_ connector: BoardConnector) {
        if selectedConnectorID == connector.id {
            selectedConnectorID = nil
        }
        modelContext.delete(connector)
        try? modelContext.save()
    }

    /// Single exit for text editing (Esc, focus loss, clicking elsewhere).
    private func endEditing() {
        guard editingItemID != nil else { return }
        editingItemID = nil
        try? modelContext.save()
    }

    /// onContinuousHover/onDrop report points in this view's own (post
    /// .scaleEffect + outer .frame) layout space, which spans
    /// extent.size * zoomScale — divide back down by the zoom and add the
    /// extent origin to get the board units item.positionX/Y are stored in.
    private func logicalPoint(from visualPoint: CGPoint) -> CGPoint {
        boardPoint(fromVisual: visualPoint, zoom: zoomScale, extentOrigin: extent.origin)
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
