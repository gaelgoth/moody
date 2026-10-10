//
//  ConnectorTests.swift
//  moodyTests
//

import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import moody

struct ConnectorTests {
    private func isClose(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) < 0.001 && abs(lhs.y - rhs.y) < 0.001
    }

    // MARK: - connectorEndpoints

    @Test func horizontalNeighboursConnectFacingEdges() throws {
        let ends = try #require(connectorEndpoints(
            from: CGRect(x: 0, y: 0, width: 100, height: 100),
            to: CGRect(x: 200, y: 0, width: 100, height: 100)
        ))
        #expect(isClose(ends.start, CGPoint(x: 100, y: 50)))
        #expect(isClose(ends.end, CGPoint(x: 200, y: 50)))
    }

    @Test func verticalNeighboursConnectFacingEdges() throws {
        let ends = try #require(connectorEndpoints(
            from: CGRect(x: 0, y: 300, width: 100, height: 100),
            to: CGRect(x: 0, y: 0, width: 100, height: 50)
        ))
        #expect(isClose(ends.start, CGPoint(x: 50, y: 300)))
        #expect(isClose(ends.end, CGPoint(x: 50, y: 50)))
    }

    @Test func diagonalLineLeavesThroughTheCorners() throws {
        let ends = try #require(connectorEndpoints(
            from: CGRect(x: 0, y: 0, width: 100, height: 100),
            to: CGRect(x: 300, y: 300, width: 100, height: 100)
        ))
        #expect(isClose(ends.start, CGPoint(x: 100, y: 100)))
        #expect(isClose(ends.end, CGPoint(x: 300, y: 300)))
    }

    @Test func overlappingBoxesHaveNoLine() {
        #expect(connectorEndpoints(
            from: CGRect(x: 10, y: 10, width: 50, height: 50),
            to: CGRect(x: 0, y: 0, width: 240, height: 160)
        ) == nil)
    }

    // MARK: - connector(between:and:in:)

    @MainActor
    @Test func connectorLookupWorksInBothDirections() throws {
        let schema = Schema([Project.self, BoardItem.self, BoardConnector.self])
        let context = try ModelContext(ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
        let project = Project(name: "Board")
        context.insert(project)
        let a = BoardItem.note(at: .zero, zIndex: 1, project: project)
        let b = BoardItem.note(at: CGPoint(x: 500, y: 0), zIndex: 2, project: project)
        let c = BoardItem.note(at: CGPoint(x: 0, y: 500), zIndex: 3, project: project)
        for note in [a, b, c] {
            context.insert(note)
        }
        let link = BoardConnector(from: a, to: b)
        context.insert(link)
        try context.save()

        #expect(connector(between: a.id, and: b.id, in: [link])?.id == link.id)
        #expect(connector(between: b.id, and: a.id, in: [link])?.id == link.id)
        #expect(connector(between: a.id, and: c.id, in: [link]) == nil)
    }
}
