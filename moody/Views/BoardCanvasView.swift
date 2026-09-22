//
//  BoardCanvasView.swift
//  moody
//
//  Wraps a plain (non-magnifying) NSScrollView for native trackpad
//  panning/elastic scrolling around a fixed-size SwiftUI document. Zoom is
//  handled entirely in SwiftUI (BoardDocumentContentView's .scaleEffect +
//  MagnificationGesture), not NSScrollView.allowsMagnification: that's an
//  AppKit-level transform applied outside SwiftUI's own view tree, which
//  SwiftUI's hit-testing has no visibility into — at any zoom other than
//  1.0 it silently breaks onHover, DragGesture, and onDrop entirely. This
//  view keeps the hosting frame's size in sync with the current zoom so
//  NSScrollView's scroll bounds match what's actually being rendered, and
//  adjusts the scroll position on every zoom change so the board zooms
//  in/out around zoomAnchor (the cursor) instead of always scaling away
//  from the document's top-left corner.
//

import AppKit
import SwiftUI

struct BoardCanvasView: NSViewRepresentable {
    let project: Project
    let items: [BoardItem]
    @Binding var zoomScale: CGFloat
    @Binding var zoomAnchor: CGPoint

    static let documentSize = CGSize(width: 20000, height: 20000)

    final class Coordinator {
        var previousZoomScale: CGFloat = 1
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context _: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true

        let hostingView = NSHostingView(
            rootView: BoardDocumentContentView(
                project: project,
                items: items,
                documentSize: Self.documentSize,
                zoomScale: $zoomScale,
                zoomAnchor: $zoomAnchor
            )
        )
        hostingView.frame = CGRect(origin: .zero, size: Self.documentSize)
        scrollView.documentView = hostingView

        DispatchQueue.main.async {
            centerScrollPosition(of: scrollView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let hostingView = scrollView.documentView as? NSHostingView<BoardDocumentContentView> else { return }
        let previousZoomScale = context.coordinator.previousZoomScale
        let scaledSize = CGSize(
            width: Self.documentSize.width * zoomScale,
            height: Self.documentSize.height * zoomScale
        )

        if hostingView.frame.size != scaledSize {
            let oldOrigin = scrollView.contentView.bounds.origin
            hostingView.frame = CGRect(origin: hostingView.frame.origin, size: scaledSize)

            if previousZoomScale != zoomScale, previousZoomScale > 0 {
                // Keep zoomAnchor (captured in the OLD, pre-resize document-
                // view coordinate space) at the same screen position: shift
                // the scroll origin by however far that point just moved.
                let ratio = zoomScale / previousZoomScale
                let newOrigin = CGPoint(
                    x: oldOrigin.x + zoomAnchor.x * (ratio - 1),
                    y: oldOrigin.y + zoomAnchor.y * (ratio - 1)
                )
                scrollView.contentView.scroll(to: newOrigin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            context.coordinator.previousZoomScale = zoomScale
        }

        hostingView.rootView = BoardDocumentContentView(
            project: project,
            items: items,
            documentSize: Self.documentSize,
            zoomScale: $zoomScale,
            zoomAnchor: $zoomAnchor
        )
    }

    private func centerScrollPosition(of scrollView: NSScrollView) {
        let visible = scrollView.contentView.bounds.size
        let origin = CGPoint(
            x: (Self.documentSize.width - visible.width) / 2,
            y: (Self.documentSize.height - visible.height) / 2
        )
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
