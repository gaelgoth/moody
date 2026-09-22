//
//  ImportGeometry.swift
//  moody
//
//  Pure layout math used when importing dropped images onto a board.
//

import Foundation

/// Scales a natural pixel size down so its longest edge is at most `maxEdge`,
/// preserving aspect ratio. Never upscales images already smaller than `maxEdge`.
func aspectFit(pixelWidth: Int, pixelHeight: Int, maxEdge: Double) -> CGSize {
    let width = Double(pixelWidth)
    let height = Double(pixelHeight)
    let scale = min(1.0, maxEdge / max(width, height))
    return CGSize(width: width * scale, height: height * scale)
}

/// Offsets the placement of the `index`-th item in a multi-file drop so items
/// don't land perfectly stacked on top of each other.
func cascadePosition(base: CGPoint, index: Int, step: Double = 24) -> CGPoint {
    let offset = step * Double(index)
    return CGPoint(x: base.x + offset, y: base.y + offset)
}

/// The z-index a newly-placed or newly-grabbed item should take to render in front
/// of every item in `existing`.
func nextZIndex(existing: [Int]) -> Int {
    (existing.max() ?? 0) + 1
}
