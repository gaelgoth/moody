//
//  BoardAlignmentTests.swift
//  moodyTests
//

import CoreGraphics
import Foundation
import Testing
@testable import moody

struct BoardAlignmentTests {
    // Group bounds: x 40...230 (mid 135), y 30...130 (mid 80).
    private let a = (id: UUID(), center: CGPoint(x: 50, y: 50), size: CGSize(width: 20, height: 40))
    private let b = (id: UUID(), center: CGPoint(x: 200, y: 120), size: CGSize(width: 60, height: 20))

    private func align(_ alignment: BoardAlignment) -> [UUID: CGPoint] {
        alignedCenters([a, b], to: alignment)
    }

    @Test func leftAlignsLeftEdgesToGroupMinXAndKeepsY() {
        let result = align(.left)
        #expect(result[a.id] == CGPoint(x: 50, y: 50))
        #expect(result[b.id] == CGPoint(x: 70, y: 120))
    }

    @Test func centerAlignsHorizontalCentersToGroupMidX() {
        let result = align(.centerX)
        #expect(result[a.id] == CGPoint(x: 135, y: 50))
        #expect(result[b.id] == CGPoint(x: 135, y: 120))
    }

    @Test func rightAlignsRightEdgesToGroupMaxX() {
        let result = align(.right)
        #expect(result[a.id] == CGPoint(x: 220, y: 50))
        #expect(result[b.id] == CGPoint(x: 200, y: 120))
    }

    @Test func topAlignsTopEdgesToGroupMinYAndKeepsX() {
        let result = align(.top)
        #expect(result[a.id] == CGPoint(x: 50, y: 50))
        #expect(result[b.id] == CGPoint(x: 200, y: 40))
    }

    @Test func middleAlignsVerticalCentersToGroupMidY() {
        let result = align(.centerY)
        #expect(result[a.id] == CGPoint(x: 50, y: 80))
        #expect(result[b.id] == CGPoint(x: 200, y: 80))
    }

    @Test func bottomAlignsBottomEdgesToGroupMaxY() {
        let result = align(.bottom)
        #expect(result[a.id] == CGPoint(x: 50, y: 110))
        #expect(result[b.id] == CGPoint(x: 200, y: 120))
    }

    @Test func emptyInputGivesNoCenters() {
        #expect(alignedCenters([], to: .left).isEmpty)
    }
}
