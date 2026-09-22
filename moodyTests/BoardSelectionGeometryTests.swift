//
//  BoardSelectionGeometryTests.swift
//  moodyTests
//

import CoreGraphics
import Foundation
import Testing
@testable import moody

struct BoardSelectionGeometryTests {
    @Test func fullyOverlappingItemIsSelected() {
        let marquee = CGRect(x: 0, y: 0, width: 200, height: 200)
        let items = [(id: UUID(), center: CGPoint(x: 100, y: 100), size: CGSize(width: 40, height: 40))]
        let result = itemsIntersecting(marquee, items: items)
        #expect(result == Set(items.map(\.id)))
    }

    @Test func partiallyOverlappingItemIsSelected() {
        let marquee = CGRect(x: 0, y: 0, width: 100, height: 100)
        let id = UUID()
        // item rect spans x 70...110, y 70...110 — overlaps the marquee's
        // bottom-right corner without being fully contained by it.
        let items = [(id: id, center: CGPoint(x: 90, y: 90), size: CGSize(width: 40, height: 40))]
        let result = itemsIntersecting(marquee, items: items)
        #expect(result == [id])
    }

    @Test func nonOverlappingItemIsExcluded() {
        let marquee = CGRect(x: 0, y: 0, width: 50, height: 50)
        let items = [(id: UUID(), center: CGPoint(x: 500, y: 500), size: CGSize(width: 40, height: 40))]
        let result = itemsIntersecting(marquee, items: items)
        #expect(result.isEmpty)
    }

    @Test func zeroSizeMarqueeRectSelectsNothingEvenCenteredOnAnItem() {
        let center = CGPoint(x: 100, y: 100)
        let marquee = CGRect(x: center.x, y: center.y, width: 0, height: 0)
        let items = [(id: UUID(), center: center, size: CGSize(width: 40, height: 40))]
        let result = itemsIntersecting(marquee, items: items)
        #expect(result.isEmpty)
    }

    @Test func emptyItemsListReturnsEmptySet() {
        let marquee = CGRect(x: 0, y: 0, width: 100, height: 100)
        let result = itemsIntersecting(marquee, items: [])
        #expect(result.isEmpty)
    }

    @Test func multipleOverlappingItemsAllReturned() {
        let marquee = CGRect(x: 0, y: 0, width: 200, height: 200)
        let idA = UUID()
        let idB = UUID()
        let idOutside = UUID()
        let items = [
            (id: idA, center: CGPoint(x: 50, y: 50), size: CGSize(width: 20, height: 20)),
            (id: idB, center: CGPoint(x: 150, y: 150), size: CGSize(width: 20, height: 20)),
            (id: idOutside, center: CGPoint(x: 1000, y: 1000), size: CGSize(width: 20, height: 20)),
        ]
        let result = itemsIntersecting(marquee, items: items)
        #expect(result == [idA, idB])
    }

    // MARK: - itemsToMove

    @Test func draggingMemberOfMultiSelectionMovesWholeSelection() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let result = itemsToMove(draggedID: a, selection: [a, b, c])
        #expect(result == [a, b, c])
    }

    @Test func draggingNonMemberMovesOnlyThatItem() {
        let a = UUID()
        let b = UUID()
        let outside = UUID()
        let result = itemsToMove(draggedID: outside, selection: [a, b])
        #expect(result == [outside])
    }

    @Test func draggingWithEmptySelectionMovesOnlyDraggedItem() {
        let a = UUID()
        let result = itemsToMove(draggedID: a, selection: [])
        #expect(result == [a])
    }

    @Test func draggingSoleSelectedItemMovesOnlyThatItem() {
        let a = UUID()
        let result = itemsToMove(draggedID: a, selection: [a])
        #expect(result == [a])
    }

    @Test func noActiveDragReturnsEmptySet() {
        let a = UUID()
        let result = itemsToMove(draggedID: nil, selection: [a])
        #expect(result.isEmpty)
    }
}
