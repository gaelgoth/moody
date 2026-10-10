//
//  ImageImportServiceTests.swift
//  moodyTests
//

import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import moody

@MainActor
struct ImageImportServiceTests {
    @Test func insertImageWritesTheFileAndAddsAnItemToTheBoard() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("moody-tests-\(UUID().uuidString)", isDirectory: true)
        let storage = FileStorageService(rootDirectory: root)
        let container = try ModelContainer(
            for: Folder.self, Project.self, BoardItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let project = Project(name: "Board")
        context.insert(project)

        try ImageImportService.insertImage(
            data: ImageFixtures.make(width: 640, height: 320, fill: ImageFixtures.red),
            fileExtension: "png",
            into: project,
            at: CGPoint(x: 10, y: 20),
            context: context,
            storage: storage
        )

        #expect(project.items.count == 1)
        let item = try #require(project.items.first)
        #expect(item.positionX == 10)
        #expect(item.positionY == 20)
        #expect(item.width == 320)
        #expect(item.height == 160)
        #expect(item.pixelWidth == 640)
        #expect(item.pixelHeight == 320)
        #expect(item.fileName.hasSuffix(".png"))
        #expect(FileManager.default.fileExists(atPath: storage.fileURL(fileName: item.fileName, projectID: project.id).path))
    }

    @Test func contentTypeOfAFileComesFromItsExtension() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try Data("x".utf8).write(to: url)
        #expect(ImageImportService.contentType(of: url) == .png)
    }
}
