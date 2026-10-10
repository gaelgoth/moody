//
//  ContainerStacking.swift
//  moody
//
//  Model writes for container stacks. Like commitGroupMove: callers save
//  afterwards, and only call these from .onEnded, toolbar/menu actions or
//  import, never mid-gesture. Membership changes pass explicit children to
//  relayout so they don't depend on when SwiftData updates `stackedItems`.
//

import CoreGraphics
import Foundation

/// Re-stacks `children` (default: the container's photos) by stackOrder,
/// renumbered 0…n-1, and resizes the container keeping its top-left fixed.
func relayout(_ container: BoardItem, children: [BoardItem]? = nil) {
    let ordered = (children ?? container.stackedItems).sorted { $0.stackOrder < $1.stackOrder }
    let topLeft = CGPoint(x: container.positionX - container.width / 2, y: container.positionY - container.height / 2)
    let layout = stackLayout(axis: container.axis, topLeft: topLeft, sizes: ordered.map(\.size))
    container.width = layout.size.width
    container.height = layout.size.height
    container.positionX = topLeft.x + layout.size.width / 2
    container.positionY = topLeft.y + layout.size.height / 2
    for (index, child) in ordered.enumerated() {
        child.stackOrder = index
        child.positionX = layout.centers[index].x
        child.positionY = layout.centers[index].y
    }
}

/// Stacks `items`, in the given order, into `container` at `index` among its
/// other photos (clamped, so `Int.max` appends), brings them in front of
/// everything, and re-lays out the target and any container they left.
func insertIntoStack(_ items: [BoardItem], container: BoardItem, at index: Int, allZIndices: [Int]) {
    let movingIDs = Set(items.map(\.id))
    let previous = Set(items.compactMap(\.container)).filter { $0.id != container.id }
    var order = container.stackedItems
        .filter { !movingIDs.contains($0.id) }
        .sorted { $0.stackOrder < $1.stackOrder }
    order.insert(contentsOf: items, at: min(max(index, 0), order.count))
    var nextZ = nextZIndex(existing: allZIndices)
    for item in items {
        item.container = container
        item.zIndex = nextZ
        nextZ += 1
    }
    for (position, item) in order.enumerated() {
        item.stackOrder = position
    }
    relayout(container, children: order)
    for old in previous {
        relayout(old, children: old.stackedItems.filter { !movingIDs.contains($0.id) })
    }
}

/// Takes `items` out of their stacks (they stay where they are) and closes
/// the gaps they leave.
func removeFromStack(_ items: [BoardItem]) {
    let ids = Set(items.map(\.id))
    let containers = Set(items.compactMap(\.container))
    for item in items {
        item.container = nil
    }
    for container in containers {
        relayout(container, children: container.stackedItems.filter { !ids.contains($0.id) })
    }
}

/// A finished drag's stack membership, after commitGroupMove has moved the
/// items: photos released over `target` join it, ordered by the drop position
/// of `dragged`; with no target, photos whose container isn't moving with
/// them leave it.
func commitStackDrop(movingItems: [BoardItem], target: BoardItem?, dragged: BoardItem?, allZIndices: [Int]) {
    let movingIDs = Set(movingItems.map(\.id))
    let photos = movingItems.filter { $0.kind == .image }
    guard let target else {
        removeFromStack(photos.filter { photo in photo.container.map { !movingIDs.contains($0.id) } ?? false })
        return
    }
    let axisValue: (BoardItem) -> Double = { target.axis == .column ? $0.positionY : $0.positionX }
    let ordered = photos.sorted { axisValue($0) < axisValue($1) }
    guard let probe = (dragged ?? ordered.first)?.center else { return }
    let others = target.stackedItems.filter { !movingIDs.contains($0.id) }
    let index = stackInsertionIndex(axis: target.axis, point: probe, existingCenters: others.map(\.center))
    insertIntoStack(ordered, container: target, at: index, allZIndices: allZIndices)
}

/// Stacks `photos` into a freshly inserted `container`, which first moves so
/// its top-left sits at the photos' top-left, ordered along its axis as they
/// sit on the board.
func stackIntoNewContainer(_ photos: [BoardItem], container: BoardItem, allZIndices: [Int]) {
    guard let minX = photos.map({ $0.positionX - $0.width / 2 }).min(),
          let minY = photos.map({ $0.positionY - $0.height / 2 }).min()
    else { return }
    container.positionX = minX + container.width / 2
    container.positionY = minY + container.height / 2
    let axisValue: (BoardItem) -> Double = { container.axis == .column ? $0.positionY : $0.positionX }
    insertIntoStack(photos.sorted { axisValue($0) < axisValue($1) }, container: container, at: 0, allZIndices: allZIndices)
}
