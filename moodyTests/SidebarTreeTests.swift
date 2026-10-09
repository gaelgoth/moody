//
//  SidebarTreeTests.swift
//  moodyTests
//

import Foundation
import SwiftData
import Testing
@testable import moody

struct SidebarTreeTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Folder.self, Project.self, BoardItem.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    // MARK: Ordering

    @Test func foldersAreSortedByNaturalNameOrder() {
        let folders = [Folder(name: "Folder 10"), Folder(name: "folder 2"), Folder(name: "Archive")]
        #expect(sortedFolders(folders).map(\.name) == ["Archive", "folder 2", "Folder 10"])
    }

    @Test func boardsAreSortedByNaturalNameOrder() {
        let boards = [Project(name: "Board 10"), Project(name: "Board 9"), Project(name: "alpha")]
        #expect(sortedProjects(boards).map(\.name) == ["alpha", "Board 9", "Board 10"])
    }

    // MARK: Descendants

    @Test func descendantProjectsIncludesEveryNestedLevel() throws {
        let context = try makeContext()
        let root = Folder(name: "Root")
        let middle = Folder(name: "Middle", parent: root)
        let leaf = Folder(name: "Leaf", parent: middle)
        let outside = Folder(name: "Outside")
        let boards = [
            Project(name: "A", folder: root),
            Project(name: "B", folder: middle),
            Project(name: "C", folder: leaf),
            Project(name: "D", folder: outside),
        ]
        for folder in [root, middle, leaf, outside] {
            context.insert(folder)
        }
        for board in boards {
            context.insert(board)
        }
        try context.save()

        #expect(Set(descendantProjects(of: root).map(\.name)) == ["A", "B", "C"])
        #expect(Set(descendantProjects(of: leaf).map(\.name)) == ["C"])
    }

    @Test func deletingAFolderRemovesItAndEverythingNested() throws {
        let context = try makeContext()
        let root = Folder(name: "Root")
        let child = Folder(name: "Child", parent: root)
        let rootBoard = Project(name: "A", folder: root)
        let childBoard = Project(name: "B", folder: child)
        let outsideBoard = Project(name: "C")
        for folder in [root, child] {
            context.insert(folder)
        }
        for board in [rootBoard, childBoard, outsideBoard] {
            context.insert(board)
        }
        try context.save()

        let removed = selectionsRemoved(byDeleting: root)
        #expect(removed == [.folder(root.id), .folder(child.id), .board(rootBoard.id), .board(childBoard.id)])
    }

    @Test func folderOutlineIsDepthFirstAndSorted() throws {
        let context = try makeContext()
        let beta = Folder(name: "Beta")
        let alpha = Folder(name: "Alpha")
        let alphaChild = Folder(name: "Alpha child", parent: alpha)
        for folder in [beta, alpha, alphaChild] {
            context.insert(folder)
        }
        try context.save()

        let outline = folderOutline([beta, alpha])
        #expect(outline.map(\.folder.name) == ["Alpha", "Alpha child", "Beta"])
        #expect(outline.map(\.depth) == [0, 1, 0])
    }

    // MARK: Moving

    @Test func folderCannotMoveIntoItselfOrADescendant() throws {
        let context = try makeContext()
        let root = Folder(name: "Root")
        let child = Folder(name: "Child", parent: root)
        let grandchild = Folder(name: "Grandchild", parent: child)
        let sibling = Folder(name: "Sibling")
        for folder in [root, child, grandchild, sibling] {
            context.insert(folder)
        }
        try context.save()

        #expect(!canMove(root, into: root))
        #expect(!canMove(root, into: child))
        #expect(!canMove(root, into: grandchild))
        #expect(canMove(root, into: sibling))
        #expect(canMove(grandchild, into: nil))
        #expect(canMove(grandchild, into: root))
    }

    @Test func movingABoardReparentsIt() throws {
        let context = try makeContext()
        let folder = Folder(name: "Folder")
        let board = Project(name: "Board")
        context.insert(folder)
        context.insert(board)
        try context.save()

        #expect(move(board, into: folder))
        #expect(board.folder === folder)
        #expect(move(board, into: nil))
        #expect(board.folder == nil)
    }

    @Test func movingAFolderReparentsItUnlessItWouldCreateACycle() throws {
        let context = try makeContext()
        let root = Folder(name: "Root")
        let child = Folder(name: "Child", parent: root)
        let other = Folder(name: "Other")
        for folder in [root, child, other] {
            context.insert(folder)
        }
        try context.save()

        #expect(move(child, into: other))
        #expect(child.parent === other)
        #expect(!move(other, into: child))
        #expect(other.parent == nil)
    }

    @Test func referenceResolvesAgainstKnownModels() throws {
        let context = try makeContext()
        let folder = Folder(name: "Folder")
        let board = Project(name: "Board")
        context.insert(folder)
        context.insert(board)
        try context.save()

        let folderReference = SidebarItemReference(selection: .folder(folder.id))
        let boardReference = SidebarItemReference(selection: .board(board.id))
        let target = Folder(name: "Target")
        context.insert(target)

        #expect(move(folderReference, into: target, folders: [folder, target], projects: [board]))
        #expect(folder.parent === target)
        #expect(move(boardReference, into: target, folders: [folder, target], projects: [board]))
        #expect(board.folder === target)
        let unknown = SidebarItemReference(selection: .board(UUID()))
        #expect(!move(unknown, into: target, folders: [folder, target], projects: [board]))
    }

    // MARK: Naming

    @Test func uniqueNameAppendsTheFirstFreeNumber() {
        #expect(uniqueName("Untitled Folder", among: []) == "Untitled Folder")
        #expect(uniqueName("Untitled Folder", among: ["Untitled Folder"]) == "Untitled Folder 2")
        #expect(uniqueName("Untitled Folder", among: ["Untitled Folder", "Untitled Folder 2"]) == "Untitled Folder 3")
    }

    @Test func renamedNameIsTrimmedAndRejectsBlank() {
        #expect(renamedName("  Mood  ") == "Mood")
        #expect(renamedName("   ") == nil)
    }

    // MARK: Drag payload

    @Test func referenceRoundTripsThroughCodable() throws {
        let reference = SidebarItemReference(selection: .folder(UUID()))
        let data = try JSONEncoder().encode(reference)
        #expect(try JSONDecoder().decode(SidebarItemReference.self, from: data) == reference)
    }
}
