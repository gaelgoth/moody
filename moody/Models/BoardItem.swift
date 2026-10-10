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
    /// resolved to a URL through FileStorageService at read time. "" for
    /// notes and containers.
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

    /// `BoardItemKind` raw value; read through `kind`. Every field below has a
    /// default so lightweight migration keeps existing boards (all photos) working.
    var kindRaw: String = "image"
    /// Note body.
    var text: String = ""
    /// `FolderColor` raw value tinting a note or container; read through `resolvedColor`.
    var colorName: String = "yellow"
    /// Container header title.
    var title: String = ""
    /// Container header SF Symbol; read through `resolvedIconName`.
    var iconName: String = "photo"
    /// `StackAxis` raw value; read through `axis`.
    var axisRaw: String = "column"
    /// The container this photo is stacked in; nil = loose on the board.
    var container: BoardItem?
    /// Position within `container`'s stack, 0 first.
    var stackOrder: Int = 0

    /// Deleting a container leaves its photos on the board, loose.
    @Relationship(deleteRule: .nullify, inverse: \BoardItem.container)
    var stackedItems: [BoardItem] = []

    /// Deleting either end of a connector deletes the connector.
    @Relationship(deleteRule: .cascade, inverse: \BoardConnector.from)
    var outgoingConnectors: [BoardConnector] = []
    @Relationship(deleteRule: .cascade, inverse: \BoardConnector.to)
    var incomingConnectors: [BoardConnector] = []

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
        kind: BoardItemKind = .image,
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
        kindRaw = kind.rawValue
        self.createdAt = createdAt
        self.project = project
    }
}
