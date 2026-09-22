//
//  BoardItem.swift
//  moody
//

import Foundation
import SwiftData

@Model
final class BoardItem {
    var id: UUID
    /// Bare leaf filename of the stored image (never an absolute path);
    /// resolved to a URL through FileStorageService at read time.
    var fileName: String

    /// Center point on the board's document coordinate space, matching
    /// SwiftUI's `.position(x:y:)`.
    var positionX: Double
    var positionY: Double

    /// On-canvas display size, fixed at import time.
    var width: Double
    var height: Double

    /// Natural decoded pixel size, kept for aspect-ratio math.
    var pixelWidth: Int
    var pixelHeight: Int

    /// Explicit stacking order; higher renders in front.
    var zIndex: Int

    var createdAt: Date
    var project: Project?

    init(
        id: UUID = UUID(),
        fileName: String,
        positionX: Double,
        positionY: Double,
        width: Double,
        height: Double,
        pixelWidth: Int,
        pixelHeight: Int,
        zIndex: Int,
        createdAt: Date = .now,
        project: Project? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.positionX = positionX
        self.positionY = positionY
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.zIndex = zIndex
        self.createdAt = createdAt
        self.project = project
    }
}
