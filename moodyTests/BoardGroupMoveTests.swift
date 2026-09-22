//
//  BoardGroupMoveTests.swift
//  moodyTests
//

import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import moody

struct BoardGroupMoveTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Project.self, BoardItem.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    @Test func shiftsPositionOfEveryMovingItem() throws {
        let context = try makeContext()
        let project = Project(name: "Test")
        context.insert(project)
        let a = BoardItem(
            fileName: "a.jpg",
            positionX: 10,
            positionY: 10,
            width: 40,
            height: 40,
            pixelWidth: 40,
            pixelHeight: 40,
            zIndex: 1,
            project: project
        )
        let b = BoardItem(
            fileName: "b.jpg",
            positionX: 20,
            positionY: 20,
            width: 40,
            height: 40,
            pixelWidth: 40,
            pixelHeight: 40,
            zIndex: 2,
            project: project
        )
        context.insert(a)
        context.insert(b)
        try context.save()

        commitGroupMove(movingItems: [a, b], allZIndices: [a.zIndex, b.zIndex], translation: CGSize(width: 5, height: -5))

        #expect(a.positionX == 15)
        #expect(a.positionY == 5)
        #expect(b.positionX == 25)
        #expect(b.positionY == 15)
    }

    @Test func leavesNonMovingItemsUntouched() throws {
        let context = try makeContext()
        let project = Project(name: "Test")
        context.insert(project)
        let moving = BoardItem(
            fileName: "a.jpg",
            positionX: 10,
            positionY: 10,
            width: 40,
            height: 40,
            pixelWidth: 40,
            pixelHeight: 40,
            zIndex: 1,
            project: project
        )
        let stationary = BoardItem(
            fileName: "b.jpg",
            positionX: 20,
            positionY: 20,
            width: 40,
            height: 40,
            pixelWidth: 40,
            pixelHeight: 40,
            zIndex: 2,
            project: project
        )
        context.insert(moving)
        context.insert(stationary)
        try context.save()

        commitGroupMove(movingItems: [moving], allZIndices: [moving.zIndex, stationary.zIndex], translation: CGSize(width: 5, height: 5))

        #expect(stationary.positionX == 20)
        #expect(stationary.positionY == 20)
    }

    @Test func assignsDistinctAscendingZIndicesAboveAllExisting() throws {
        let context = try makeContext()
        let project = Project(name: "Test")
        context.insert(project)
        let a = BoardItem(
            fileName: "a.jpg",
            positionX: 0,
            positionY: 0,
            width: 40,
            height: 40,
            pixelWidth: 40,
            pixelHeight: 40,
            zIndex: 1,
            project: project
        )
        let b = BoardItem(
            fileName: "b.jpg",
            positionX: 0,
            positionY: 0,
            width: 40,
            height: 40,
            pixelWidth: 40,
            pixelHeight: 40,
            zIndex: 5,
            project: project
        )
        let c = BoardItem(
            fileName: "c.jpg",
            positionX: 0,
            positionY: 0,
            width: 40,
            height: 40,
            pixelWidth: 40,
            pixelHeight: 40,
            zIndex: 3,
            project: project
        )
        context.insert(a)
        context.insert(b)
        context.insert(c)
        try context.save()

        commitGroupMove(movingItems: [a, c], allZIndices: [a.zIndex, b.zIndex, c.zIndex], translation: .zero)

        #expect(a.zIndex > 5)
        #expect(c.zIndex > 5)
        #expect(a.zIndex != c.zIndex)
        #expect(b.zIndex == 5)
    }

    @Test func preservesRelativeFrontToBackOrderAmongMovingItems() throws {
        let context = try makeContext()
        let project = Project(name: "Test")
        context.insert(project)
        // c was in front of a before the move (zIndex 4 > 1).
        let a = BoardItem(
            fileName: "a.jpg",
            positionX: 0,
            positionY: 0,
            width: 40,
            height: 40,
            pixelWidth: 40,
            pixelHeight: 40,
            zIndex: 1,
            project: project
        )
        let c = BoardItem(
            fileName: "c.jpg",
            positionX: 0,
            positionY: 0,
            width: 40,
            height: 40,
            pixelWidth: 40,
            pixelHeight: 40,
            zIndex: 4,
            project: project
        )
        context.insert(a)
        context.insert(c)
        try context.save()

        commitGroupMove(movingItems: [a, c], allZIndices: [a.zIndex, c.zIndex], translation: .zero)

        #expect(c.zIndex > a.zIndex)
    }

    @Test func singleItemMovingItemsBehavesLikeSoloDragCommit() throws {
        let context = try makeContext()
        let project = Project(name: "Test")
        context.insert(project)
        let a = BoardItem(
            fileName: "a.jpg",
            positionX: 10,
            positionY: 10,
            width: 40,
            height: 40,
            pixelWidth: 40,
            pixelHeight: 40,
            zIndex: 1,
            project: project
        )
        context.insert(a)
        try context.save()

        commitGroupMove(movingItems: [a], allZIndices: [a.zIndex], translation: CGSize(width: 3, height: 4))

        #expect(a.positionX == 13)
        #expect(a.positionY == 14)
        #expect(a.zIndex == 2)
    }
}
