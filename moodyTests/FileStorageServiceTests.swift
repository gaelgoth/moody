//
//  FileStorageServiceTests.swift
//  moodyTests
//

import Foundation
import Testing
@testable import moody

struct FileStorageServiceTests {
    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("moody-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func writingAFileCreatesTheProjectImagesDirectoryAndTheFile() throws {
        let root = try makeTempRoot()
        let storage = FileStorageService(rootDirectory: root)
        let projectID = UUID()
        let fileName = "\(UUID().uuidString).jpg"

        try storage.write(data: Data("fake-image-bytes".utf8), fileName: fileName, projectID: projectID)

        let fileURL = storage.fileURL(fileName: fileName, projectID: projectID)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try Data(contentsOf: fileURL) == Data("fake-image-bytes".utf8))
    }

    @Test func deletingAFileRemovesOnlyThatFile() throws {
        let root = try makeTempRoot()
        let storage = FileStorageService(rootDirectory: root)
        let projectID = UUID()
        let keepFileName = "keep.jpg"
        let deleteFileName = "delete.jpg"

        try storage.write(data: Data("keep".utf8), fileName: keepFileName, projectID: projectID)
        try storage.write(data: Data("delete".utf8), fileName: deleteFileName, projectID: projectID)

        try storage.deleteFile(fileName: deleteFileName, projectID: projectID)

        #expect(FileManager.default.fileExists(atPath: storage.fileURL(fileName: keepFileName, projectID: projectID).path))
        #expect(!FileManager.default.fileExists(atPath: storage.fileURL(fileName: deleteFileName, projectID: projectID).path))
    }

    @Test func deletingAProjectDirectoryRemovesAllItsFiles() throws {
        let root = try makeTempRoot()
        let storage = FileStorageService(rootDirectory: root)
        let projectID = UUID()

        try storage.write(data: Data("one".utf8), fileName: "one.jpg", projectID: projectID)
        try storage.write(data: Data("two".utf8), fileName: "two.jpg", projectID: projectID)

        try storage.deleteProjectDirectory(projectID: projectID)

        #expect(!FileManager.default.fileExists(atPath: storage.imagesDirectory(projectID: projectID).path))
    }
}
