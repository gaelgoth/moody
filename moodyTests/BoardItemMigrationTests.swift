//
//  BoardItemMigrationTests.swift
//  moodyTests
//
//  Opens an on-disk store written with the pre-annotations schema (frozen
//  copies of Folder / Project / BoardItem as of debc39d) using today's
//  schema, so a lightweight-migration break shows up here and not as a
//  library that won't open.
//

import Foundation
import SwiftData
import Testing
@testable import moody

enum PreAnnotationsSchema {
    @Model
    final class Folder {
        var id: UUID
        var name: String
        var iconName: String
        var colorName: String
        var isExpanded: Bool
        var createdAt: Date
        var parent: Folder?

        @Relationship(deleteRule: .cascade, inverse: \Folder.parent)
        var subfolders: [Folder] = []

        @Relationship(deleteRule: .cascade, inverse: \Project.folder)
        var projects: [Project] = []

        init(name: String) {
            id = UUID()
            self.name = name
            iconName = "folder"
            colorName = "blue"
            isExpanded = true
            createdAt = .now
        }
    }

    @Model
    final class Project {
        var id: UUID
        var name: String
        var createdAt: Date
        var folder: Folder?
        var showsGrid: Bool = false
        var usesDarkBackground: Bool = false

        @Relationship(deleteRule: .cascade, inverse: \BoardItem.project)
        var items: [BoardItem] = []

        init(name: String) {
            id = UUID()
            self.name = name
            createdAt = .now
        }
    }

    @Model
    final class BoardItem {
        var id: UUID
        var fileName: String
        var positionX: Double
        var positionY: Double
        var width: Double
        var height: Double
        var pixelWidth: Int
        var pixelHeight: Int
        var zIndex: Int
        var createdAt: Date
        var project: Project?

        init(fileName: String, project: Project) {
            id = UUID()
            self.fileName = fileName
            positionX = 10
            positionY = 20
            width = 300
            height = 200
            pixelWidth = 600
            pixelHeight = 400
            zIndex = 3
            createdAt = .now
            self.project = project
        }
    }
}

struct BoardItemMigrationTests {
    @Test func aPreAnnotationsLibraryOpensWithEveryPhotoIntact() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("moody-migration-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let schema = Schema([
                PreAnnotationsSchema.Folder.self,
                PreAnnotationsSchema.Project.self,
                PreAnnotationsSchema.BoardItem.self,
            ])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let context = ModelContext(container)
            let project = PreAnnotationsSchema.Project(name: "Old Board")
            context.insert(project)
            context.insert(PreAnnotationsSchema.BoardItem(fileName: "photo.png", project: project))
            try context.save()
        }

        let schema = Schema([Folder.self, Project.self, BoardItem.self, BoardConnector.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let items = try ModelContext(container).fetch(FetchDescriptor<BoardItem>())

        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.kind == .image)
        #expect(item.fileName == "photo.png")
        #expect(item.center == CGPoint(x: 10, y: 20))
        #expect(item.container == nil)
        #expect(item.project?.name == "Old Board")
    }
}
