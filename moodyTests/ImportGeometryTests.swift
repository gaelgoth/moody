//
//  ImportGeometryTests.swift
//  moodyTests
//

import CoreGraphics
import Foundation
import Testing
@testable import moody

struct ImportGeometryTests {
    // MARK: - aspectFit

    @Test func aspectFitScalesDownLandscapeImageToMaxEdge() {
        let size = aspectFit(pixelWidth: 4000, pixelHeight: 2000, maxEdge: 320)
        #expect(size.width == 320)
        #expect(size.height == 160)
    }

    @Test func aspectFitScalesDownPortraitImageToMaxEdge() {
        let size = aspectFit(pixelWidth: 2000, pixelHeight: 4000, maxEdge: 320)
        #expect(size.width == 160)
        #expect(size.height == 320)
    }

    @Test func aspectFitScalesDownSquareImageToMaxEdge() {
        let size = aspectFit(pixelWidth: 1000, pixelHeight: 1000, maxEdge: 320)
        #expect(size.width == 320)
        #expect(size.height == 320)
    }

    @Test func aspectFitNeverUpscalesImagesSmallerThanMaxEdge() {
        let size = aspectFit(pixelWidth: 100, pixelHeight: 50, maxEdge: 320)
        #expect(size.width == 100)
        #expect(size.height == 50)
    }

    // MARK: - cascadePosition

    @Test func cascadePositionLeavesFirstItemAtBase() {
        let point = cascadePosition(base: CGPoint(x: 100, y: 100), index: 0)
        #expect(point == CGPoint(x: 100, y: 100))
    }

    @Test func cascadePositionOffsetsSubsequentItemsDiagonally() {
        let point = cascadePosition(base: CGPoint(x: 100, y: 100), index: 3, step: 24)
        #expect(point == CGPoint(x: 172, y: 172))
    }

    // MARK: - nextZIndex

    @Test func nextZIndexIsOneWhenNoItemsExist() {
        #expect(nextZIndex(existing: []) == 1)
    }

    @Test func nextZIndexIsOneGreaterThanTheCurrentMaximum() {
        #expect(nextZIndex(existing: [1, 5, 2]) == 6)
    }

    // MARK: - appendedImportCenter

    @Test func appendedImportCenterPutsTheTopLeftAtTheOriginOnAnEmptyBoard() {
        let center = appendedImportCenter(contentBounds: nil, size: CGSize(width: 200, height: 100))
        #expect(center == CGPoint(x: 100, y: 50))
    }

    @Test func appendedImportCenterPlacesTheImageRightOfContentTopAligned() {
        let bounds = CGRect(x: -50, y: 10, width: 300, height: 400)
        let center = appendedImportCenter(contentBounds: bounds, size: CGSize(width: 200, height: 100), gap: 40)
        #expect(center == CGPoint(x: 390, y: 60))
    }
}
