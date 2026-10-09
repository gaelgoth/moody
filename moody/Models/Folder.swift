//
//  Folder.swift
//  moody
//
//  A sidebar folder grouping boards (and other folders) into a tree. A nil
//  `parent` means top level. Deleting a folder cascades to its subfolders and
//  boards — but, as with `Project`, only the database rows: callers must also
//  delete each descendant board's image directory (see `descendantProjects`).
//

import Foundation
import SwiftData

@Model
final class Folder {
    var id: UUID
    var name: String
    /// SF Symbol name, normally one of `FolderIcon.all`; read through
    /// `resolvedIconName` so an unknown value falls back to the default.
    var iconName: String
    /// `FolderColor` raw value; read through `resolvedColor`.
    var colorName: String
    /// Disclosure state in the sidebar, persisted so it survives relaunch.
    var isExpanded: Bool
    var createdAt: Date
    var parent: Folder?

    @Relationship(deleteRule: .cascade, inverse: \Folder.parent)
    var subfolders: [Folder] = []

    @Relationship(deleteRule: .cascade, inverse: \Project.folder)
    var projects: [Project] = []

    init(
        id: UUID = UUID(),
        name: String,
        iconName: String = FolderIcon.defaultName,
        colorName: String = FolderColor.defaultColor.rawValue,
        isExpanded: Bool = true,
        createdAt: Date = .now,
        parent: Folder? = nil
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.colorName = colorName
        self.isExpanded = isExpanded
        self.createdAt = createdAt
        self.parent = parent
    }
}
