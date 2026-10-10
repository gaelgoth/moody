//
//  BorderToolServiceTests.swift
//  moodyTests
//

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import moody

@MainActor
struct BorderToolServiceTests {
    // MARK: - uniqueBorderFileName

    @Test func uniqueNameAddsTheBorderSuffix() {
        #expect(uniqueBorderFileName(base: "Beach", fileExtension: "jpg", taken: []) == "Beach border.jpg")
    }

    @Test func uniqueNameSkipsATakenNameIgnoringCase() {
        let name = uniqueBorderFileName(base: "Beach", fileExtension: "jpg", taken: ["beach border.jpg"])
        #expect(name == "Beach border 2.jpg")
    }

    @Test func uniqueNameKeepsCountingPastTakenNumbers() {
        let taken: Set = ["beach border.jpg", "beach border 2.jpg"]
        #expect(uniqueBorderFileName(base: "Beach", fileExtension: "jpg", taken: taken) == "Beach border 3.jpg")
    }

    // MARK: - loadSource

    @Test func loadingAFileKeepsItsBytesTypeAndNameWithoutExtension() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("moody-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Beach.png")
        let data = try ImageFixtures.make(fill: ImageFixtures.red)
        try data.write(to: url)

        let source = try BorderToolService.loadSource(at: url)

        #expect(source.name == "Beach")
        #expect(source.contentType == .png)
        #expect(source.data == data)
    }

    // MARK: - render

    @Test func renderBordersARasterSource() async throws {
        let source = try BorderSource(name: "Red", data: ImageFixtures.make(fill: ImageFixtures.red), contentType: .png)
        let output = try await BorderToolService.render(source, percent: 10, color: ImageFixtures.white)
        #expect(output.pixelWidth == 120)
        #expect(output.pixelHeight == 70)
    }
}
