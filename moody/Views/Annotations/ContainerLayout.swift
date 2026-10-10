//
//  ContainerLayout.swift
//  moody
//
//  Pure geometry for container stacks: photos keep their own size and sit
//  edge to edge below a header band, centered on the cross axis.
//

import CoreGraphics
import Foundation

enum StackMetrics {
    static let headerHeight: Double = 32
    static let padding: Double = 12
    static let gap: Double = 12
    static let minSize = CGSize(width: 240, height: 160)
}

/// Child centers and container size for a stack whose top-left is `topLeft`.
func stackLayout(axis: StackAxis, topLeft: CGPoint, sizes: [CGSize]) -> (centers: [CGPoint], size: CGSize) {
    let pad = StackMetrics.padding
    let header = StackMetrics.headerHeight
    let spacing = StackMetrics.gap * Double(max(sizes.count - 1, 0))
    var centers: [CGPoint] = []
    switch axis {
    case .column:
        let width = max(StackMetrics.minSize.width, (sizes.map(\.width).max() ?? 0) + 2 * pad)
        let height = max(StackMetrics.minSize.height, header + 2 * pad + sizes.map(\.height).reduce(0, +) + spacing)
        var y = topLeft.y + header + pad
        for size in sizes {
            centers.append(CGPoint(x: topLeft.x + width / 2, y: y + size.height / 2))
            y += size.height + StackMetrics.gap
        }
        return (centers, CGSize(width: width, height: height))
    case .row:
        let width = max(StackMetrics.minSize.width, 2 * pad + sizes.map(\.width).reduce(0, +) + spacing)
        let height = max(StackMetrics.minSize.height, header + 2 * pad + (sizes.map(\.height).max() ?? 0))
        let midY = topLeft.y + header + (height - header) / 2
        var x = topLeft.x + pad
        for size in sizes {
            centers.append(CGPoint(x: x + size.width / 2, y: midY))
            x += size.width + StackMetrics.gap
        }
        return (centers, CGSize(width: width, height: height))
    }
}

/// Where a photo released at `point` goes in a stack: the number of existing
/// children whose center lies before it along the axis.
func stackInsertionIndex(axis: StackAxis, point: CGPoint, existingCenters: [CGPoint]) -> Int {
    existingCenters.filter { axis == .column ? $0.y < point.y : $0.x < point.x }.count
}

/// Id of the front-most item containing `point`; `items` are ordered back to front.
func topmostContaining(_ point: CGPoint, items: [(id: UUID, center: CGPoint, size: CGSize)]) -> UUID? {
    items.last { item in
        CGRect(
            x: item.center.x - item.size.width / 2,
            y: item.center.y - item.size.height / 2,
            width: item.size.width,
            height: item.size.height
        ).contains(point)
    }?.id
}
