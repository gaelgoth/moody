//
//  BoardItemModelTests.swift
//  moodyTests
//

import Foundation
import SwiftData
import Testing
@testable import moody

struct BoardItemModelTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Project.self, BoardItem.self, BoardConnector.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeItem(in project: Project, context: ModelContext, kind: BoardItemKind = .image) -> BoardItem {
        let item = BoardItem(
            fileName: kind == .image ? "\(UUID().uuidString).png" : "",
            positionX: 0,
            positionY: 0,
            width: 100,
            height: 100,
            pixelWidth: 100,
            pixelHeight: 100,
            zIndex: 1,
            kind: kind,
            project: project
        )
        context.insert(item)
        return item
    }

    @Test func itemsDefaultToTheImageKind() throws {
        let context = try makeContext()
        let project = Project(name: "Board")
        context.insert(project)
        let item = BoardItem(
            fileName: "a.png", positionX: 0, positionY: 0, width: 10, height: 10,
            pixelWidth: 10, pixelHeight: 10, zIndex: 1, project: project
        )
        context.insert(item)
        #expect(item.kind == .image)
        #expect(item.kindRaw == "image")
    }

    @Test func unknownKindFallsBackToImage() throws {
        let context = try makeContext()
        let project = Project(name: "Board")
        context.insert(project)
        let item = makeItem(in: project, context: context, kind: .note)
        item.kindRaw = "sticker"
        #expect(item.kind == .image)
    }

    @Test func unknownColorAndIconFallBackToDefaults() throws {
        let context = try makeContext()
        let project = Project(name: "Board")
        context.insert(project)
        let note = makeItem(in: project, context: context, kind: .note)
        note.colorName = "plaid"
        note.iconName = "not.a.symbol"
        #expect(note.resolvedColor == .yellow)
        #expect(note.resolvedIconName == "photo")
    }

    @Test func deletingAnItemDeletesItsConnectors() throws {
        let context = try makeContext()
        let project = Project(name: "Board")
        context.insert(project)
        let a = makeItem(in: project, context: context)
        let b = makeItem(in: project, context: context, kind: .note)
        context.insert(BoardConnector(from: a, to: b))
        try context.save()

        context.delete(b)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<BoardConnector>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<BoardItem>()).count == 1)
    }

    @Test func deletingAProjectDeletesItsConnectors() throws {
        let context = try makeContext()
        let project = Project(name: "Board")
        context.insert(project)
        let a = makeItem(in: project, context: context)
        let b = makeItem(in: project, context: context)
        context.insert(BoardConnector(from: a, to: b))
        try context.save()

        context.delete(project)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<BoardConnector>()).isEmpty)
    }
}
