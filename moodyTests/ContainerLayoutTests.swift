//
//  ContainerLayoutTests.swift
//  moodyTests
//

import CoreGraphics
import Foundation
import Testing
@testable import moody

struct ContainerLayoutTests {
    // MARK: - stackLayout

    @Test func emptyContainerHasTheMinimumSize() {
        let layout = stackLayout(axis: .column, topLeft: .zero, sizes: [])
        #expect(layout.centers.isEmpty)
        #expect(layout.size == StackMetrics.minSize)
    }

    @Test func columnStacksBelowTheHeaderCenteredHorizontally() {
        let layout = stackLayout(axis: .column, topLeft: .zero, sizes: [
            CGSize(width: 100, height: 50),
            CGSize(width: 300, height: 200),
        ])
        // width = 300 + 2*12, height = 32 + 2*12 + 50 + 12 + 200
        #expect(layout.size == CGSize(width: 324, height: 318))
        #expect(layout.centers == [CGPoint(x: 162, y: 69), CGPoint(x: 162, y: 206)])
    }

    @Test func rowStacksLeftToRightCenteredInTheContentBand() {
        let layout = stackLayout(axis: .row, topLeft: .zero, sizes: [
            CGSize(width: 100, height: 50),
            CGSize(width: 60, height: 80),
        ])
        // width = max(240, 12 + 100 + 12 + 60 + 12), height = max(160, 32 + 24 + 80)
        #expect(layout.size == CGSize(width: 240, height: 160))
        #expect(layout.centers == [CGPoint(x: 62, y: 96), CGPoint(x: 154, y: 96)])
    }

    @Test func layoutIsRelativeToTheTopLeft() {
        let layout = stackLayout(axis: .column, topLeft: CGPoint(x: 1000, y: -500), sizes: [CGSize(width: 100, height: 50)])
        #expect(layout.centers == [CGPoint(x: 1120, y: -431)])
    }

    // MARK: - stackInsertionIndex

    @Test func insertionIndexCountsChildrenBeforeThePointAlongTheAxis() {
        let centers = [CGPoint(x: 0, y: 100), CGPoint(x: 0, y: 200), CGPoint(x: 0, y: 300)]
        #expect(stackInsertionIndex(axis: .column, point: CGPoint(x: 0, y: 50), existingCenters: centers) == 0)
        #expect(stackInsertionIndex(axis: .column, point: CGPoint(x: 0, y: 250), existingCenters: centers) == 2)
        #expect(stackInsertionIndex(axis: .column, point: CGPoint(x: 0, y: 900), existingCenters: centers) == 3)
        #expect(stackInsertionIndex(axis: .row, point: CGPoint(x: 50, y: 900), existingCenters: centers) == 3)
    }

    // MARK: - topmostContaining

    @Test func topmostContainingPicksTheFrontMostHit() {
        let back = UUID()
        let front = UUID()
        let items = [
            (id: back, center: CGPoint(x: 0, y: 0), size: CGSize(width: 100, height: 100)),
            (id: front, center: CGPoint(x: 20, y: 0), size: CGSize(width: 100, height: 100)),
        ]
        #expect(topmostContaining(CGPoint(x: 10, y: 0), items: items) == front)
        #expect(topmostContaining(CGPoint(x: -45, y: 0), items: items) == back)
        #expect(topmostContaining(CGPoint(x: 500, y: 0), items: items) == nil)
    }

    // MARK: - expandingContainers

    @Test func expandingAContainerAddsItsStackedPhotos() {
        let container = UUID()
        let photo = UUID()
        let loose = UUID()
        #expect(expandingContainers([container, loose], children: [container: [photo]]) == [container, photo, loose])
        #expect(expandingContainers([], children: [container: [photo]]).isEmpty)
    }
}
