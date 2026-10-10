//
//  ConnectorLayerView.swift
//  moody
//
//  Connector lines, drawn above the background and below every item.
//  Endpoints come from each item's live rect (including the in-flight drag
//  translation), so lines follow a drag without any model write. Each line
//  is clickable along a 12pt band around it.
//

import SwiftUI

struct ConnectorLayerView: View {
    let connectors: [BoardConnector]
    /// Subtracted so board coordinates map to the parent's local space.
    let extentOrigin: CGPoint
    let isDarkBoard: Bool
    let selectedConnectorID: UUID?
    let liveRect: (BoardItem) -> CGRect
    let onSelect: (UUID) -> Void
    let onUnlink: (BoardConnector) -> Void

    var body: some View {
        ZStack {
            ForEach(connectors) { connector in
                if let from = connector.from, let to = connector.to,
                   let ends = connectorEndpoints(from: liveRect(from), to: liveRect(to)) {
                    line(from: ends.start, to: ends.end, isSelected: connector.id == selectedConnectorID)
                        .onTapGesture { onSelect(connector.id) }
                        .contextMenu {
                            Button("Unlink") { onUnlink(connector) }
                        }
                }
            }
        }
    }

    private func line(from start: CGPoint, to end: CGPoint, isSelected: Bool) -> some View {
        let path = Path { path in
            path.move(to: CGPoint(x: start.x - extentOrigin.x, y: start.y - extentOrigin.y))
            path.addLine(to: CGPoint(x: end.x - extentOrigin.x, y: end.y - extentOrigin.y))
        }
        return path
            .stroke(isSelected ? Color.accentColor : lineColor, lineWidth: isSelected ? 3 : 2)
            .contentShape(path.strokedPath(StrokeStyle(lineWidth: 12)))
    }

    private var lineColor: Color {
        isDarkBoard ? Color.white.opacity(0.6) : Color.black.opacity(0.45)
    }
}
