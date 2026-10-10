//
//  BoardItemKind.swift
//  moody
//
//  What a BoardItem is. Stored as plain strings so an unknown value (e.g.
//  from a newer build) falls back instead of failing to load the board.
//

import CoreGraphics
import Foundation

enum BoardItemKind: String {
    case image
    case note
    case container
}

enum StackAxis: String {
    case row
    case column
}

extension BoardItem {
    var kind: BoardItemKind {
        BoardItemKind(rawValue: kindRaw) ?? .image
    }

    var axis: StackAxis {
        get { StackAxis(rawValue: axisRaw) ?? .column }
        set { axisRaw = newValue.rawValue }
    }

    var resolvedColor: FolderColor {
        FolderColor(rawValue: colorName) ?? (kind == .container ? FolderColor.defaultColor : .yellow)
    }

    var resolvedIconName: String {
        FolderIcon.all.contains(iconName) ? iconName : "photo"
    }

    var center: CGPoint {
        CGPoint(x: positionX, y: positionY)
    }

    var size: CGSize {
        CGSize(width: width, height: height)
    }
}
