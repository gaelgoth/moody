//
//  CanvasExtent.swift
//  moody
//
//  Pure geometry for the board canvas's content-aware scroll extent.
//
//  Three coordinate spaces:
//  - board: unbounded; where BoardItem.positionX/Y live.
//  - visual: the hosting NSView's (document view's) own space, spanning
//    extent.size * zoom, with (0, 0) at extent.origin.
//  - scroll: the NSClipView bounds origin, in visual units.
//  The extent is recomputed from the content and the visible rect, so the
//  scroll bars only ever cover the photos plus a margin.
//

import CoreGraphics

/// Zoom limits shared by pinch-zoom and Zoom to Fit.
enum BoardZoom {
    static let minScale: CGFloat = 0.1
    static let maxScale: CGFloat = 4
}

/// Union of every item's rect (center ± size/2); nil for an empty board.
func boardContentBounds(_ items: [(center: CGPoint, size: CGSize)]) -> CGRect? {
    items.reduce(nil as CGRect?) { partial, item in
        let rect = CGRect(
            x: item.center.x - item.size.width / 2,
            y: item.center.y - item.size.height / 2,
            width: item.size.width,
            height: item.size.height
        )
        return partial?.union(rect) ?? rect
    }
}

/// The scrollable board-space rect: the content padded by `marginFraction` of a
/// viewport on every side, always grown to include `visibleRect` so a layout
/// pass never yanks the current view away. Half a viewport (not a full one)
/// keeps some content on screen even at the extreme scroll positions.
func canvasExtent(contentBounds: CGRect?, visibleRect: CGRect, marginFraction: CGFloat = 0.5) -> CGRect {
    guard let contentBounds else { return visibleRect }
    let padded = contentBounds.insetBy(dx: -visibleRect.width * marginFraction, dy: -visibleRect.height * marginFraction)
    return padded.union(visibleRect)
}

/// Decides which extent a layout pass may actually apply, given the freshly
/// `proposed` one:
/// - Routine refreshes (`allowShrink == false`, e.g. the re-render on every
///   hover move) only ever grow the extent; dropping stale area is left to
///   deliberate moments (scroll end, wheel quiet, resize, zoom), so it never
///   happens mid mouse-wheel scroll.
/// - While the pointer is down a gesture may be live, and its start/translation
///   values are in local coordinates that an origin shift would silently
///   invalidate, so any change that moves the origin is deferred (nil).
/// An empty `current` (nothing laid out yet) is always replaced.
func nextCanvasExtent(current: CGRect, proposed: CGRect, allowShrink: Bool, isPointerDown: Bool) -> CGRect? {
    guard !current.isEmpty else { return proposed }
    let candidate = allowShrink ? proposed : proposed.union(current)
    if isPointerDown, candidate.origin != current.origin {
        return nil
    }
    return candidate
}

/// The board-space rect currently on screen.
func visibleBoardRect(scrollOrigin: CGPoint, viewportSize: CGSize, zoom: CGFloat, extentOrigin: CGPoint) -> CGRect {
    CGRect(
        x: extentOrigin.x + scrollOrigin.x / zoom,
        y: extentOrigin.y + scrollOrigin.y / zoom,
        width: viewportSize.width / zoom,
        height: viewportSize.height / zoom
    )
}

/// The clip-view scroll origin that puts `visibleOrigin` (board space) at the viewport's top-left.
func scrollOrigin(forVisibleOrigin visibleOrigin: CGPoint, zoom: CGFloat, extentOrigin: CGPoint) -> CGPoint {
    CGPoint(x: (visibleOrigin.x - extentOrigin.x) * zoom, y: (visibleOrigin.y - extentOrigin.y) * zoom)
}

/// Converts a point in the hosting view's post-.scaleEffect space to board space.
func boardPoint(fromVisual visualPoint: CGPoint, zoom: CGFloat, extentOrigin: CGPoint) -> CGPoint {
    CGPoint(x: extentOrigin.x + visualPoint.x / zoom, y: extentOrigin.y + visualPoint.y / zoom)
}

/// The new visible-rect origin after a zoom change that keeps `anchor` (board
/// space) at the same on-screen position.
func zoomedVisibleOrigin(anchor: CGPoint, visibleRect: CGRect, oldZoom: CGFloat, newZoom: CGFloat) -> CGPoint {
    let ratio = oldZoom / newZoom
    return CGPoint(
        x: anchor.x - (anchor.x - visibleRect.minX) * ratio,
        y: anchor.y - (anchor.y - visibleRect.minY) * ratio
    )
}

/// The visible-rect origin that centers `center` (board space) in the viewport.
func centeredVisibleOrigin(on center: CGPoint, viewportSize: CGSize, zoom: CGFloat) -> CGPoint {
    CGPoint(x: center.x - viewportSize.width / zoom / 2, y: center.y - viewportSize.height / zoom / 2)
}

/// Zoom and visible origin that frame `contentBounds` inside the viewport with
/// `padding` points of screen space around it. Never zooms in past 1.0, and
/// never below BoardZoom.minScale.
func fitToContent(_ contentBounds: CGRect, viewportSize: CGSize, padding: CGFloat = 40) -> (zoom: CGFloat, visibleOrigin: CGPoint) {
    let availableWidth = max(viewportSize.width - 2 * padding, 1)
    let availableHeight = max(viewportSize.height - 2 * padding, 1)
    let rawZoom = min(availableWidth / max(contentBounds.width, 1), availableHeight / max(contentBounds.height, 1))
    let zoom = min(max(rawZoom, BoardZoom.minScale), 1)
    let center = CGPoint(x: contentBounds.midX, y: contentBounds.midY)
    return (zoom, centeredVisibleOrigin(on: center, viewportSize: viewportSize, zoom: zoom))
}
