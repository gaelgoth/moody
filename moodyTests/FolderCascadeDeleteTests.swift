//
//  FolderCascadeDeleteTests.swift
//  moodyTests
//

import Foundation
import SwiftData
import Testing
@testable import moody

struct FolderCascadeDeleteTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Folder.self, Project.self, BoardItem.self, BoardConnector.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func insertItem(into project: Project, context: ModelContext) {
        let item = BoardItem(
            fileName: "\(UUID().uuidString).png",
            positionX: 0,
            positionY: 0,
            width: 100,
            height: 100,
            pixelWidth: 100,
            pixelHeight: 100,
            zIndex: 0,
            project: project
        )
        context.insert(item)
    }

    @Test func deletingFolderCascadesSubfoldersBoardsAndItems() throws {
        let context = try makeContext()
        let root = Folder(name: "Root")
        let child = Folder(name: "Child", parent: root)
        let rootBoard = Project(name: "In root", folder: root)
        let childBoard = Project(name: "In child", folder: child)
        let topLevelBoard = Project(name: "Top level")
        for model in [root, child] {
            context.insert(model)
        }
        for board in [rootBoard, childBoard, topLevelBoard] {
            context.insert(board)
            insertItem(into: board, context: context)
        }
        try context.save()

        context.delete(root)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Folder>()).isEmpty)
        let remainingProjects = try context.fetch(FetchDescriptor<Project>())
        #expect(remainingProjects.map(\.name) == ["Top level"])
        #expect(try context.fetch(FetchDescriptor<BoardItem>()).count == 1)
    }

    @Test func deletingBoardInsideFolderKeepsTheFolder() throws {
        let context = try makeContext()
        let folder = Folder(name: "Folder")
        let board = Project(name: "Board", folder: folder)
        context.insert(folder)
        context.insert(board)
        try context.save()

        context.delete(board)
        try context.save()

        let folders = try context.fetch(FetchDescriptor<Folder>())
        #expect(folders.map(\.name) == ["Folder"])
        #expect(folders.first?.projects.isEmpty == true)
    }
}
