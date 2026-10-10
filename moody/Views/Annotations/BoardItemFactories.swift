//
//  BoardItemFactories.swift
//  moody
//
//  New non-photo board items. Callers insert and save.
//

import CoreGraphics
import Foundation

extension BoardItem {
    static func note(at center: CGPoint, zIndex: Int, project: Project) -> BoardItem {
        BoardItem(
            fileName: "",
            positionX: center.x,
            positionY: center.y,
            width: NoteMetrics.width,
            height: NoteMetrics.minHeight,
            pixelWidth: 0,
            pixelHeight: 0,
            zIndex: zIndex,
            kind: .note,
            project: project
        )
    }

    static func container(axis: StackAxis, at center: CGPoint, zIndex: Int, project: Project) -> BoardItem {
        let item = BoardItem(
            fileName: "",
            positionX: center.x,
            positionY: center.y,
            width: StackMetrics.minSize.width,
            height: StackMetrics.minSize.height,
            pixelWidth: 0,
            pixelHeight: 0,
            zIndex: zIndex,
            kind: .container,
            project: project
        )
        item.axis = axis
        item.colorName = FolderColor.defaultColor.rawValue
        return item
    }
}
