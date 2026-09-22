//
//  ProjectCascadeDeleteTests.swift
//  moodyTests
//

import Testing
import SwiftData
@testable import moody

struct ProjectCascadeDeleteTests {

    @Test func deletingProjectCascadeDeletesItsBoardItems() throws {
        let schema = Schema([Project.self, BoardItem.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let project = Project(name: "Test Board")
        context.insert(project)

        for index in 0..<3 {
            let item = BoardItem(
                fileName: "\(index).jpg",
                positionX: 0,
                positionY: 0,
                width: 100,
                height: 100,
                pixelWidth: 100,
                pixelHeight: 100,
                zIndex: index,
                project: project
            )
            context.insert(item)
        }
        try context.save()

        context.delete(project)
        try context.save()

        let remainingItems = try context.fetch(FetchDescriptor<BoardItem>())
        #expect(remainingItems.isEmpty)
    }
}
