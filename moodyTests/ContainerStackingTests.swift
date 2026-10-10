//
//  ContainerStackingTests.swift
//  moodyTests
//

import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import moody

@MainActor
struct ContainerStackingTests {
    private func setUp() throws -> (ModelContext, Project) {
        let schema = Schema([Project.self, BoardItem.self, BoardConnector.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let context = try ModelContext(ModelContainer(for: schema, configurations: [configuration]))
        let project = Project(name: "Board")
        context.insert(project)
        return (context, project)
    }

    /// An empty container whose top-left is (0, 0).
    private func makeContainer(_ project: Project, _ context: ModelContext, axis: StackAxis = .column) -> BoardItem {
        let container = BoardItem.container(axis: axis, at: CGPoint(x: 120, y: 80), zIndex: 1, project: project)
        context.insert(container)
        return container
    }

    private func makePhoto(
        _ project: Project,
        _ context: ModelContext,
        height: Double = 50,
        at center: CGPoint = CGPoint(x: 900, y: 900),
        zIndex: Int = 2
    ) -> BoardItem {
        let photo = BoardItem(
            fileName: "\(UUID().uuidString).png", positionX: center.x, positionY: center.y, width: 100, height: height,
            pixelWidth: 100, pixelHeight: Int(height), zIndex: zIndex, project: project
        )
        context.insert(photo)
        return photo
    }

    @Test func containerFactoryMakesAnEmptyBlueStack() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context, axis: .row)
        #expect(container.kind == .container)
        #expect(container.axis == .row)
        #expect(container.size == StackMetrics.minSize)
        #expect(container.resolvedColor == FolderColor.defaultColor)
    }

    @Test func insertingIntoAnEmptyColumnStacksBelowTheHeader() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context)
        let photo = makePhoto(project, context)

        insertIntoStack([photo], container: container, at: 0, allZIndices: [1, 2])

        #expect(photo.container?.id == container.id)
        #expect(photo.center == CGPoint(x: 120, y: 69))
        #expect(container.size == StackMetrics.minSize)
    }

    @Test func insertedPhotosComeInFrontOfEverything() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context)
        let photo = makePhoto(project, context, zIndex: 2)

        insertIntoStack([photo], container: container, at: 0, allZIndices: [1, 2, 7])

        #expect(photo.zIndex == 8)
    }

    @Test func insertingAtAnIndexOrdersTheStack() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context)
        let a = makePhoto(project, context)
        let b = makePhoto(project, context)
        let c = makePhoto(project, context)
        insertIntoStack([a, b], container: container, at: 0, allZIndices: [])

        insertIntoStack([c], container: container, at: 1, allZIndices: [])

        #expect([a.stackOrder, c.stackOrder, b.stackOrder] == [0, 1, 2] as [Int])
        #expect(a.positionY < c.positionY)
        #expect(c.positionY < b.positionY)
    }

    @Test func reinsertingAtItsOwnIndexKeepsTheOrder() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context)
        let a = makePhoto(project, context)
        let b = makePhoto(project, context)
        insertIntoStack([a, b], container: container, at: 0, allZIndices: [])

        insertIntoStack([a], container: container, at: 0, allZIndices: [])

        #expect([a.stackOrder, b.stackOrder] == [0, 1] as [Int])
    }

    @Test func theContainerGrowsDownwardKeepingItsTopLeft() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context)
        let tall = makePhoto(project, context, height: 300)

        insertIntoStack([tall], container: container, at: 0, allZIndices: [])

        #expect(container.height == 32 + 24 + 300)
        #expect(container.positionY - container.height / 2 == 0)
        #expect(container.positionX - container.width / 2 == 0)
    }

    @Test func removingFromAStackKeepsThePhotoWhereItIsAndClosesTheGap() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context)
        let a = makePhoto(project, context)
        let b = makePhoto(project, context)
        insertIntoStack([a, b], container: container, at: 0, allZIndices: [])
        let firstSlot = a.center
        a.positionX = 2000

        removeFromStack([a])

        #expect(a.container == nil)
        #expect(a.positionX == 2000)
        #expect(b.center == firstSlot)
        #expect(b.stackOrder == 0)
    }

    @Test func droppingALoosePhotoOnAContainerStacksItAtTheDropPosition() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context)
        let a = makePhoto(project, context)
        let b = makePhoto(project, context)
        insertIntoStack([a, b], container: container, at: 0, allZIndices: [])
        let loose = makePhoto(project, context, at: CGPoint(x: 120, y: a.positionY + 1))

        commitStackDrop(movingItems: [loose], target: container, dragged: loose, allZIndices: [])

        #expect([a.stackOrder, loose.stackOrder, b.stackOrder] == [0, 1, 2] as [Int])
    }

    @Test func draggingAStackedPhotoOutRemovesIt() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context)
        let photo = makePhoto(project, context)
        insertIntoStack([photo], container: container, at: 0, allZIndices: [])

        commitStackDrop(movingItems: [photo], target: nil, dragged: photo, allZIndices: [])

        #expect(photo.container == nil)
    }

    @Test func draggingAContainerWithItsPhotosKeepsThemStacked() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context)
        let photo = makePhoto(project, context)
        insertIntoStack([photo], container: container, at: 0, allZIndices: [])

        commitStackDrop(movingItems: [container, photo], target: nil, dragged: container, allZIndices: [])

        #expect(photo.container?.id == container.id)
    }

    @Test func movingAPhotoBetweenContainersRelayoutsBoth() throws {
        let (context, project) = try setUp()
        let left = makeContainer(project, context)
        let right = BoardItem.container(axis: .column, at: CGPoint(x: 1120, y: 80), zIndex: 1, project: project)
        context.insert(right)
        let a = makePhoto(project, context)
        let b = makePhoto(project, context)
        insertIntoStack([a, b], container: left, at: 0, allZIndices: [])
        let firstSlot = a.center

        insertIntoStack([a], container: right, at: 0, allZIndices: [])

        #expect(a.container?.id == right.id)
        #expect(a.positionX == 1120)
        #expect(b.center == firstSlot)
    }

    @Test func deletingAContainerLeavesItsPhotosLooseAndDropsItsConnectors() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context)
        let photo = makePhoto(project, context)
        insertIntoStack([photo], container: container, at: 0, allZIndices: [])
        context.insert(BoardConnector(from: photo, to: container))
        try context.save()
        let position = photo.center

        deleteBoardItems([container], context: context)

        #expect(try context.fetch(FetchDescriptor<BoardItem>()).map(\.id) == [photo.id])
        #expect(photo.container == nil)
        #expect(photo.center == position)
        #expect(try context.fetch(FetchDescriptor<BoardConnector>()).isEmpty)
    }

    @Test func deletingAStackedPhotoClosesTheGap() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context)
        let a = makePhoto(project, context)
        let b = makePhoto(project, context)
        insertIntoStack([a, b], container: container, at: 0, allZIndices: [])
        try context.save()
        let firstSlot = a.center
        let storage = FileStorageService(rootDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("moody-tests-\(UUID().uuidString)", isDirectory: true))

        deleteBoardItems([a], context: context, storage: storage)

        #expect(b.center == firstSlot)
        #expect(b.stackOrder == 0)
    }

    @Test func stackingIntoANewContainerOrdersPhotosAlongTheAxis() throws {
        let (context, project) = try setUp()
        let right = makePhoto(project, context, at: CGPoint(x: 500, y: 100))
        let left = makePhoto(project, context, at: CGPoint(x: 200, y: 300))
        let container = makeContainer(project, context, axis: .row)

        stackIntoNewContainer([right, left], container: container, allZIndices: [1, 2])

        #expect(left.container?.id == container.id)
        #expect(right.container?.id == container.id)
        #expect([left.stackOrder, right.stackOrder] == [0, 1] as [Int])
    }

    @Test func aNewContainerStartsAtThePhotosTopLeft() throws {
        let (context, project) = try setUp()
        // Bounds top-left: (150, 75) and (450, 275) → (150, 75).
        let a = makePhoto(project, context, at: CGPoint(x: 200, y: 100))
        let b = makePhoto(project, context, at: CGPoint(x: 500, y: 300))
        let container = makeContainer(project, context)

        stackIntoNewContainer([a, b], container: container, allZIndices: [1, 2])

        #expect(container.positionX - container.width / 2 == 150)
        #expect(container.positionY - container.height / 2 == 75)
    }

    @Test func photosInANewContainerAreInFrontOfIt() throws {
        let (context, project) = try setUp()
        let photo = makePhoto(project, context, zIndex: 2)
        let container = BoardItem.container(axis: .column, at: .zero, zIndex: 3, project: project)
        context.insert(container)

        stackIntoNewContainer([photo], container: container, allZIndices: [2, 3])

        #expect(photo.zIndex > container.zIndex)
    }

    @Test func stackingIntoANewContainerClosesTheGapInTheOldOne() throws {
        let (context, project) = try setUp()
        let old = makeContainer(project, context)
        let a = makePhoto(project, context)
        let b = makePhoto(project, context)
        insertIntoStack([a, b], container: old, at: 0, allZIndices: [])
        let firstSlot = a.center
        let new = BoardItem.container(axis: .row, at: .zero, zIndex: 9, project: project)
        context.insert(new)

        stackIntoNewContainer([a], container: new, allZIndices: [9])

        #expect(a.container?.id == new.id)
        #expect(b.center == firstSlot)
        #expect(b.stackOrder == 0)
    }
}
