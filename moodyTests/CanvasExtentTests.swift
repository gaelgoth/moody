//
//  CanvasExtentTests.swift
//  moodyTests
//

import CoreGraphics
import Foundation
import Testing
@testable import moody

struct CanvasExtentTests {
    private func isClose(_ lhs: CGPoint, _ rhs: CGPoint, tolerance: CGFloat = 0.001) -> Bool {
        abs(lhs.x - rhs.x) < tolerance && abs(lhs.y - rhs.y) < tolerance
    }

    // MARK: - boardContentBounds

    @Test func contentBoundsIsNilForNoItems() {
        #expect(boardContentBounds([]) == nil)
    }

    @Test func contentBoundsUnionsEveryItemRect() {
        let bounds = boardContentBounds([
            (center: CGPoint(x: 0, y: 0), size: CGSize(width: 100, height: 50)),
            (center: CGPoint(x: 300, y: 200), size: CGSize(width: 20, height: 20)),
        ])
        #expect(bounds == CGRect(x: -50, y: -25, width: 360, height: 235))
    }

    // MARK: - canvasExtent

    @Test func emptyBoardExtentIsTheVisibleRect() {
        let visible = CGRect(x: 120, y: -40, width: 800, height: 600)
        #expect(canvasExtent(contentBounds: nil, visibleRect: visible) == visible)
    }

    @Test func extentPadsContentByHalfAViewportAndIncludesVisibleRect() {
        let extent = canvasExtent(
            contentBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
            visibleRect: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        // padded content: x -400...500, y -300...400; union with visible 0...800, 0...600
        #expect(extent == CGRect(x: -400, y: -300, width: 1200, height: 900))
    }

    @Test func extentStretchesToKeepAFarAwayViewportReachable() {
        let extent = canvasExtent(
            contentBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
            visibleRect: CGRect(x: 5000, y: 5000, width: 800, height: 600)
        )
        #expect(extent == CGRect(x: -400, y: -300, width: 6200, height: 5900))
    }

    @Test func scrollingToTheExtremeEdgeStillShowsContent() {
        let content = CGRect(x: 0, y: 0, width: 100, height: 100)
        let viewport = CGSize(width: 800, height: 600)
        let extent = canvasExtent(contentBounds: content, visibleRect: CGRect(origin: .zero, size: viewport))
        let topLeftMost = CGRect(origin: extent.origin, size: viewport)
        let bottomRightMost = CGRect(
            x: extent.maxX - viewport.width, y: extent.maxY - viewport.height,
            width: viewport.width, height: viewport.height
        )
        #expect(topLeftMost.intersects(content))
        #expect(bottomRightMost.intersects(content))
    }

    // MARK: - nextCanvasExtent

    private let current = CGRect(x: -400, y: -300, width: 1200, height: 900)

    @Test func routineRefreshNeverShrinksTheExtent() {
        // Hover-driven refreshes mid mouse-wheel scroll must not drop the stale area yet.
        let proposed = CGRect(x: 0, y: 0, width: 800, height: 600)
        #expect(nextCanvasExtent(current: current, proposed: proposed, allowShrink: false, isPointerDown: false) == current)
    }

    @Test func deliberateRefreshShrinksTheExtent() {
        let proposed = CGRect(x: 0, y: 0, width: 800, height: 600)
        #expect(nextCanvasExtent(current: current, proposed: proposed, allowShrink: true, isPointerDown: false) == proposed)
    }

    @Test func trailingGrowthIsAppliedWhilePointerIsDown() {
        let proposed = CGRect(x: -400, y: -300, width: 2000, height: 900)
        #expect(nextCanvasExtent(current: current, proposed: proposed, allowShrink: false, isPointerDown: true) == proposed)
    }

    @Test func originShiftIsDeferredWhilePointerIsDown() {
        // An import finishing up-left mid-drag would shift every local coordinate under the live gesture.
        let proposed = CGRect(x: -3000, y: -300, width: 3800, height: 900)
        #expect(nextCanvasExtent(current: current, proposed: proposed, allowShrink: false, isPointerDown: true) == nil)
    }

    @Test func originShiftIsAppliedOncePointerIsUp() {
        let proposed = CGRect(x: -3000, y: -300, width: 3800, height: 900)
        #expect(nextCanvasExtent(current: current, proposed: proposed, allowShrink: false, isPointerDown: false) == proposed)
    }

    @Test func firstExtentIsAppliedEvenWhilePointerIsDown() {
        let proposed = CGRect(x: -3000, y: -300, width: 3800, height: 900)
        #expect(nextCanvasExtent(current: .zero, proposed: proposed, allowShrink: false, isPointerDown: true) == proposed)
    }

    // MARK: - coordinate conversions

    @Test func visibleBoardRectAccountsForZoomAndExtentOrigin() {
        let rect = visibleBoardRect(
            scrollOrigin: CGPoint(x: 200, y: 100), viewportSize: CGSize(width: 800, height: 600),
            zoom: 2, extentOrigin: CGPoint(x: -400, y: -300)
        )
        #expect(rect == CGRect(x: -300, y: -250, width: 400, height: 300))
    }

    @Test func scrollOriginIsTheInverseOfVisibleBoardRect() {
        let origin = scrollOrigin(forVisibleOrigin: CGPoint(x: -300, y: -250), zoom: 2, extentOrigin: CGPoint(x: -400, y: -300))
        #expect(origin == CGPoint(x: 200, y: 100))
    }

    @Test func boardPointFromVisualUndoesZoomThenAddsExtentOrigin() {
        let point = boardPoint(fromVisual: CGPoint(x: 200, y: 100), zoom: 2, extentOrigin: CGPoint(x: -400, y: -300))
        #expect(point == CGPoint(x: -300, y: -250))
    }

    @Test func visibleOriginSurvivesExtentOriginShift() {
        // A photo was dropped far up-left, so the extent grows on its leading edge.
        // Re-deriving the scroll origin for the new extent must keep the same board rect on screen.
        let viewport = CGSize(width: 800, height: 600)
        let oldExtentOrigin = CGPoint(x: -400, y: -300)
        let visible = visibleBoardRect(
            scrollOrigin: CGPoint(x: 300, y: 200), viewportSize: viewport, zoom: 1.5, extentOrigin: oldExtentOrigin
        )
        let newExtent = canvasExtent(contentBounds: CGRect(x: -3000, y: -2000, width: 3200, height: 2200), visibleRect: visible)
        #expect(newExtent.minX < oldExtentOrigin.x)
        let newScroll = scrollOrigin(forVisibleOrigin: visible.origin, zoom: 1.5, extentOrigin: newExtent.origin)
        let after = visibleBoardRect(scrollOrigin: newScroll, viewportSize: viewport, zoom: 1.5, extentOrigin: newExtent.origin)
        #expect(isClose(after.origin, visible.origin))
    }

    // MARK: - zoom anchoring

    @Test func zoomingKeepsTheAnchorAtTheSameScreenOffset() {
        let origin = zoomedVisibleOrigin(
            anchor: CGPoint(x: 100, y: 100), visibleRect: CGRect(x: 0, y: 0, width: 800, height: 600),
            oldZoom: 1, newZoom: 2
        )
        #expect(origin == CGPoint(x: 50, y: 50))
    }

    @Test func repeatedZoomTicksKeepAnchorFixedOnScreen() {
        let anchor = CGPoint(x: 300, y: 200)
        let viewport = CGSize(width: 800, height: 600)
        var visibleOrigin = CGPoint.zero
        var zoom: CGFloat = 1
        for newZoom in [1.25, 1.5, 2, 0.5, 0.1] as [CGFloat] {
            let visible = CGRect(origin: visibleOrigin, size: CGSize(width: viewport.width / zoom, height: viewport.height / zoom))
            visibleOrigin = zoomedVisibleOrigin(anchor: anchor, visibleRect: visible, oldZoom: zoom, newZoom: newZoom)
            zoom = newZoom
            let screenOffset = CGPoint(x: (anchor.x - visibleOrigin.x) * zoom, y: (anchor.y - visibleOrigin.y) * zoom)
            #expect(isClose(screenOffset, CGPoint(x: 300, y: 200)))
        }
    }

    // MARK: - centering and fit

    @Test func centeredVisibleOriginAtZoomOne() {
        let origin = centeredVisibleOrigin(on: CGPoint(x: 50, y: 50), viewportSize: CGSize(width: 800, height: 600), zoom: 1)
        #expect(origin == CGPoint(x: -350, y: -250))
    }

    @Test func centeredVisibleOriginAccountsForZoom() {
        let origin = centeredVisibleOrigin(on: CGPoint(x: 50, y: 50), viewportSize: CGSize(width: 800, height: 600), zoom: 2)
        #expect(origin == CGPoint(x: -150, y: -100))
    }

    @Test func centeringOnLegacyContentPutsItMidViewport() throws {
        // Boards created before this change store positions around the old 20000x20000 document's center.
        let content = try #require(boardContentBounds([(center: CGPoint(x: 10000, y: 10000), size: CGSize(width: 320, height: 240))]))
        let viewport = CGSize(width: 1000, height: 700)
        let origin = centeredVisibleOrigin(on: CGPoint(x: content.midX, y: content.midY), viewportSize: viewport, zoom: 1)
        let visible = CGRect(origin: origin, size: viewport)
        #expect(visible.contains(content))
        #expect(visible.midX == 10000 && visible.midY == 10000)
    }

    @Test func fitZoomsOutToFrameLargeContentWithPadding() {
        let fit = fitToContent(CGRect(x: 0, y: 0, width: 1840, height: 1040), viewportSize: CGSize(width: 1000, height: 600))
        #expect(fit.zoom == 0.5)
        #expect(fit.visibleOrigin == CGPoint(x: -80, y: -80))
    }

    @Test func fitNeverMagnifiesSmallContentPastActualSize() {
        let fit = fitToContent(CGRect(x: 0, y: 0, width: 100, height: 100), viewportSize: CGSize(width: 1000, height: 600))
        #expect(fit.zoom == 1)
        #expect(fit.visibleOrigin == CGPoint(x: -450, y: -250))
    }

    @Test func fitClampsToMinimumZoomForHugeContent() {
        let fit = fitToContent(CGRect(x: 0, y: 0, width: 100_000, height: 100_000), viewportSize: CGSize(width: 1000, height: 600))
        #expect(fit.zoom == BoardZoom.minScale)
    }
}
