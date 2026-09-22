//
//  BoardSelectionGeometry.swift
//  moody
//
//  Pure geometry for marquee (rubber-band) multi-select on the board canvas.
//

import Foundation
import CoreGraphics

/// Ids of items whose bounding rect (center ± size/2) intersects `marqueeRect`.
/// Uses ordinary rect intersection ("any overlap selects", matching Finder's
/// rubber-band semantics — not full containment). A zero-size marqueeRect
/// (e.g. a plain click) is explicitly rejected by guard clause below — without it,
/// CGRect.intersects(_:) can spuriously report intersection when a degenerate rect's
/// single point lies within another rect's bounds. This special-casing is what makes
/// "click empty canvas clears selection" work correctly.
func itemsIntersecting(
    _ marqueeRect: CGRect,
    items: [(id: UUID, center: CGPoint, size: CGSize)]
) -> Set<UUID> {
    // Zero-size marquee never selects anything
    guard marqueeRect.width > 0 && marqueeRect.height > 0 else {
        return Set()
    }

    return Set(items.compactMap { item in
        let rect = CGRect(
            x: item.center.x - item.size.width / 2,
            y: item.center.y - item.size.height / 2,
            width: item.size.width,
            height: item.size.height
        )
        return rect.intersects(marqueeRect) ? item.id : nil
    })
}

/// Ids of items a drag should move: the whole `selection` if `draggedID` is
/// a member of a multi-item selection, otherwise just `draggedID` alone.
/// `nil` `draggedID` (no drag in progress) yields an empty set.
func itemsToMove(draggedID: UUID?, selection: Set<UUID>) -> Set<UUID> {
    guard let draggedID else { return [] }
    if selection.contains(draggedID), selection.count > 1 {
        return selection
    }
    return [draggedID]
}
