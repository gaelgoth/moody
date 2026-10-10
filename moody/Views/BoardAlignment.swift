//
//  BoardAlignment.swift
//  moody
//
//  Aligns selected items to the selection's bounding box (Keynote/Figma
//  semantics). Pure: BoardView writes the returned centers to the model.
//

import CoreGraphics
import Foundation

enum BoardAlignment: CaseIterable {
    case left, centerX, right, top, centerY, bottom

    var title: String {
        switch self {
        case .left: "Align Left"
        case .centerX: "Align Center"
        case .right: "Align Right"
        case .top: "Align Top"
        case .centerY: "Align Middle"
        case .bottom: "Align Bottom"
        }
    }

    var systemImage: String {
        switch self {
        case .left: "align.horizontal.left"
        case .centerX: "align.horizontal.center"
        case .right: "align.horizontal.right"
        case .top: "align.vertical.top"
        case .centerY: "align.vertical.center"
        case .bottom: "align.vertical.bottom"
        }
    }
}

/// New centers aligning every item to the group's bounding box; only the
/// aligned axis changes.
func alignedCenters(_ items: [(id: UUID, center: CGPoint, size: CGSize)], to alignment: BoardAlignment) -> [UUID: CGPoint] {
    guard let bounds = boardContentBounds(items.map { (center: $0.center, size: $0.size) }) else { return [:] }
    var result: [UUID: CGPoint] = [:]
    for item in items {
        var center = item.center
        switch alignment {
        case .left: center.x = bounds.minX + item.size.width / 2
        case .centerX: center.x = bounds.midX
        case .right: center.x = bounds.maxX - item.size.width / 2
        case .top: center.y = bounds.minY + item.size.height / 2
        case .centerY: center.y = bounds.midY
        case .bottom: center.y = bounds.maxY - item.size.height / 2
        }
        result[item.id] = center
    }
    return result
}
