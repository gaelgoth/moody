//
//  BoardGrid.swift
//  moody
//
//  Background grid geometry. Lines sit on board-space multiples of the
//  spacing, so they stay pinned to the board when extent.origin shifts.
//

import SwiftUI

let boardGridSpacing: CGFloat = 40

/// Local offsets, within an extent spanning `origin ..< origin + length`, of
/// every board-space multiple of `spacing`.
func gridLineOffsets(origin: CGFloat, length: CGFloat, spacing: CGFloat) -> [CGFloat] {
    let first = (origin / spacing).rounded(.up) * spacing - origin
    return Array(stride(from: first, to: length, by: spacing))
}

/// Fills the board white/black and optionally draws the grid. Rendered
/// inside BoardDocumentContentView's .scaleEffect, so it zooms with content.
struct BoardBackgroundView: View {
    let extent: CGRect
    let showsGrid: Bool
    let isDark: Bool

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(isDark ? .black : .white))
            guard showsGrid else { return }
            var lines = Path()
            for x in gridLineOffsets(origin: extent.minX, length: size.width, spacing: boardGridSpacing) {
                lines.move(to: CGPoint(x: x, y: 0))
                lines.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in gridLineOffsets(origin: extent.minY, length: size.height, spacing: boardGridSpacing) {
                lines.move(to: CGPoint(x: 0, y: y))
                lines.addLine(to: CGPoint(x: size.width, y: y))
            }
            let lineColor: Color = isDark ? .white.opacity(0.12) : .black.opacity(0.08)
            context.stroke(lines, with: .color(lineColor), lineWidth: 1)
        }
    }
}
