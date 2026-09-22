//
//  BoardGroupMove.swift
//  moody
//
//  Commits a completed drag (solo or group) to the model. Mutates
//  already-inserted @Model objects in place; the caller must call
//  modelContext.save() afterwards. Must only be invoked once a drag
//  gesture has ended, never mid-.onChanged — see BoardDocumentContentView
//  for why a mid-gesture @Model write is unsafe.
//

import Foundation

/// Shifts positionX/positionY of every item in `movingItems` by `translation`,
/// and reassigns each an ascending zIndex above every value in `allZIndices`
/// so the whole group comes to front together, preserving movingItems' own
/// relative front-to-back order. A single-item `movingItems` array is the
/// solo-drag case.
func commitGroupMove(movingItems: [BoardItem], allZIndices: [Int], translation: CGSize) {
    let ordered = movingItems.sorted { $0.zIndex < $1.zIndex }
    var nextZ = nextZIndex(existing: allZIndices)
    for item in ordered {
        item.positionX += translation.width
        item.positionY += translation.height
        item.zIndex = nextZ
        nextZ += 1
    }
}
