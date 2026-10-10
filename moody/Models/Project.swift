//
//  Project.swift
//  moody
//

import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID
    var name: String
    var createdAt: Date
    /// Containing sidebar folder; nil means the board sits at top level.
    var folder: Folder?
    /// Board look, toggled from BoardView's toolbar. Defaults keep
    /// SwiftData's lightweight migration working for existing stores.
    var showsGrid: Bool = false
    var usesDarkBackground: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \BoardItem.project)
    var items: [BoardItem] = []

    init(id: UUID = UUID(), name: String, createdAt: Date = .now, folder: Folder? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.folder = folder
    }
}
