//
//  BoardDeletionTests.swift
//  moodyTests
//

import Foundation
import SwiftData
import Testing
@testable import moody

@MainActor
struct BoardDeletionTests {
    private func makeStorage() -> FileStorageService {
        FileStorageService(rootDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("moody-tests-\(UUID().uuidString)", isDirectory: true))
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Project.self, BoardItem.self, BoardConnector.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContext(ModelContainer(for: schema, configurations: [configuration]))
    }

    private func makeItem(_ fileName: String, kind: BoardItemKind, project: Project, context: ModelContext) -> BoardItem {
        let item = BoardItem(
            fileName: fileName, positionX: 0, positionY: 0, width: 100, height: 100,
            pixelWidth: 100, pixelHeight: 100, zIndex: 1, kind: kind, project: project
        )
        context.insert(item)
        return item
    }

    @Test func deletingAPhotoRemovesItsRowAndFile() throws {
        let storage = makeStorage()
        let context = try makeContext()
        let project = Project(name: "Board")
        context.insert(project)
        try storage.write(data: Data("x".utf8), fileName: "a.png", projectID: project.id)
        let photo = makeItem("a.png", kind: .image, project: project, context: context)
        try context.save()

        deleteBoardItems([photo], context: context, storage: storage)

        #expect(try context.fetch(FetchDescriptor<BoardItem>()).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: storage.fileURL(fileName: "a.png", projectID: project.id).path))
    }

    @Test func deletingAPhotoWithAMissingFileStillRemovesIt() throws {
        let context = try makeContext()
        let project = Project(name: "Board")
        context.insert(project)
        let photo = makeItem("gone.png", kind: .image, project: project, context: context)
        try context.save()

        deleteBoardItems([photo], context: context, storage: makeStorage())

        #expect(try context.fetch(FetchDescriptor<BoardItem>()).isEmpty)
    }

    @Test func deletingANoteLeavesOtherItemsAlone() throws {
        let context = try makeContext()
        let project = Project(name: "Board")
        context.insert(project)
        let note = makeItem("", kind: .note, project: project, context: context)
        let photo = makeItem("a.png", kind: .image, project: project, context: context)
        try context.save()

        deleteBoardItems([note], context: context, storage: makeStorage())

        #expect(try context.fetch(FetchDescriptor<BoardItem>()).map(\.id) == [photo.id])
    }
}
