//
//  ConnectorGeometry.swift
//  moody
//
//  Where connector lines start and end, and finding the link between two items.
//

import CoreGraphics
import Foundation

/// A line between two boxes runs edge to edge along the segment joining their
/// centers. nil when the boxes overlap: there's no gap to draw across (e.g. a
/// photo linked to its own container).
func connectorEndpoints(from: CGRect, to: CGRect) -> (start: CGPoint, end: CGPoint)? {
    guard !from.intersects(to) else { return nil }
    return (
        edgePoint(of: from, toward: CGPoint(x: to.midX, y: to.midY)),
        edgePoint(of: to, toward: CGPoint(x: from.midX, y: from.midY))
    )
}

/// Where the ray from `rect`'s center toward `target` crosses its boundary.
private func edgePoint(of rect: CGRect, toward target: CGPoint) -> CGPoint {
    let dx = target.x - rect.midX
    let dy = target.y - rect.midY
    let scaleX = dx == 0 ? .infinity : rect.width / 2 / abs(dx)
    let scaleY = dy == 0 ? .infinity : rect.height / 2 / abs(dy)
    let scale = min(scaleX, scaleY)
    return CGPoint(x: rect.midX + dx * scale, y: rect.midY + dy * scale)
}

/// The connector in `connectors` linking items `a` and `b`, in either direction.
func connector(between a: UUID, and b: UUID, in connectors: [BoardConnector]) -> BoardConnector? {
    connectors.first { ($0.from?.id == a && $0.to?.id == b) || ($0.from?.id == b && $0.to?.id == a) }
}
