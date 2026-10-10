//
//  NoteGeometryTests.swift
//  moodyTests
//

import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import moody

struct NoteGeometryTests {
    @Test func emptyNoteUsesTheMinimumHeight() {
        #expect(noteHeight(text: "") == NoteMetrics.minHeight)
    }

    @Test func longTextGrowsPastTheMinimum() {
        let text = String(repeating: "Warm stone and long shadows. ", count: 20)
        #expect(noteHeight(text: text) > NoteMetrics.minHeight)
    }

    @Test func moreTextIsNeverShorter() {
        let short = String(repeating: "word ", count: 30)
        #expect(noteHeight(text: short + short) >= noteHeight(text: short))
    }

    @Test func fittingANoteKeepsItsTopEdge() throws {
        let schema = Schema([Project.self, BoardItem.self, BoardConnector.self])
        let context = try ModelContext(ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
        let project = Project(name: "Board")
        context.insert(project)
        let note = BoardItem.note(at: CGPoint(x: 0, y: 100), zIndex: 1, project: project)
        context.insert(note)
        let top = note.positionY - note.height / 2

        note.text = String(repeating: "Warm stone and long shadows. ", count: 20)
        fitNoteHeight(note)

        #expect(note.height > NoteMetrics.minHeight)
        #expect(abs((note.positionY - note.height / 2) - top) < 0.001)
    }

    @Test func noteFactoryMakesAYellowNoteCard() {
        let project = Project(name: "Board")
        let note = BoardItem.note(at: CGPoint(x: 5, y: 6), zIndex: 3, project: project)
        #expect(note.kind == .note)
        #expect(note.width == NoteMetrics.width)
        #expect(note.height == NoteMetrics.minHeight)
        #expect(note.resolvedColor == .yellow)
        #expect(note.fileName.isEmpty)
        #expect(note.positionX == 5)
        #expect(note.zIndex == 3)
    }
}
