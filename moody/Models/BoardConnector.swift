//
//  BoardConnector.swift
//  moody
//
//  A straight line linking two board items (photo, note or container).
//  Deleting either end deletes the connector (cascade rules on BoardItem).
//

import Foundation
import SwiftData

@Model
final class BoardConnector {
    var id: UUID
    var from: BoardItem?
    var to: BoardItem?
    var createdAt: Date

    init(id: UUID = UUID(), from: BoardItem?, to: BoardItem?, createdAt: Date = .now) {
        self.id = id
        self.from = from
        self.to = to
        self.createdAt = createdAt
    }
}
