//
//  BoardCanvasView.swift
//  moody
//
//  Wraps a plain (non-magnifying) NSScrollView for native trackpad
//  panning/elastic scrolling around the SwiftUI board. Zoom is handled
//  entirely in SwiftUI (BoardDocumentContentView's .scaleEffect +
//  MagnificationGesture), not NSScrollView.allowsMagnification: that's an
//  AppKit-level transform applied outside SwiftUI's own view tree, which
//  SwiftUI's hit-testing has no visibility into — at any zoom other than
//  1.0 it silently breaks onHover, DragGesture, and onDrop entirely.
//  ⌘+scroll (wheel or trackpad) is the second zoom input: BoardScrollView
//  diverts those events to the coordinator, which zooms around the cursor
//  through the same applyZoom path.
//
//  The scrollable area is content-aware, not a fixed document: the
//  coordinator keeps an `extent` (board space) = the photos' bounds padded by
//  half a viewport, unioned with whatever is on screen right now, and sizes
//  the hosting view to extent.size * zoom. Every layout pass that moves
//  extent.origin also moves the scroll origin by the same amount, so the
//  view never jumps. The extent is never shrunk during a live (trackpad /
//  scroller) scroll — that would fight momentum and elastic bounce — nor on
//  the routine re-render SwiftUI does on every hover move — only when a
//  live scroll ends, 250 ms after the last discrete wheel tick, or on
//  resize / zoom. While the mouse button is down, origin shifts wait until
//  release so a live drag's local coordinates stay valid. See
//  CanvasExtent.swift for the math.
//

import AppKit
import SwiftUI

/// Lets BoardView's toolbar trigger canvas actions that need the live
/// NSScrollView (viewport size, scroll position), which only
/// BoardCanvasView's coordinator owns.
final class BoardCanvasController {
    var zoomToFit: () -> Void = {}
    /// Board-space center of what's on screen, where new notes and containers land.
    var visibleCenter: () -> CGPoint = { .zero }
}

struct BoardCanvasView: NSViewRepresentable {
    let project: Project
    let items: [BoardItem]
    let connectors: [BoardConnector]
    @Binding var zoomScale: CGFloat
    /// Board-space point to keep under the cursor while zooming; nil = viewport center.
    @Binding var zoomAnchor: CGPoint?
    /// Owned by BoardView so its toolbar can act on the selection.
    @Binding var selectedItemIDs: Set<UUID>
    @Binding var editingItemID: UUID?
    @Binding var selectedConnectorID: UUID?
    let controller: BoardCanvasController
    /// ⌫ / ⌦ on this board's window; returns whether the key was used.
    let onDeleteKey: () -> Bool
    let itemMenuActions: BoardItemMenuActions

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        coordinator.parent = self
        let scrollView = BoardScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.backgroundColor = project.usesDarkBackground ? .black : .white
        scrollView.documentView = NSHostingView(rootView: coordinator.makeContent())
        coordinator.attach(to: scrollView)
        coordinator.installDeleteKeyMonitor()
        scrollView.onCommandScroll = { [weak coordinator] event in coordinator?.zoomFromScroll(event) }
        controller.zoomToFit = { [weak coordinator] in coordinator?.zoomToFit() }
        controller.visibleCenter = { [weak coordinator] in coordinator?.visibleCenter() ?? .zero }
        return scrollView
    }

    static func dismantleNSView(_: NSScrollView, coordinator: Coordinator) {
        coordinator.removeDeleteKeyMonitor()
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        // Elastic overscroll shows the scroll view itself, past the hosting view.
        scrollView.backgroundColor = project.usesDarkBackground ? .black : .white
        if zoomScale != coordinator.zoom {
            coordinator.applyZoom(zoomScale, anchor: zoomAnchor)
        } else {
            coordinator.refreshExtent()
        }
    }
}

extension BoardCanvasView {
    final class Coordinator: NSObject {
        var parent: BoardCanvasView
        private(set) var zoom: CGFloat
        private var extent: CGRect = .zero
        private weak var scrollView: NSScrollView?
        private var isLiveScrolling = false
        /// Set while applyLayout moves the frame/scroll origin, so the bounds
        /// notifications it causes don't schedule another layout.
        private var isApplyingLayout = false
        private var needsInitialCentering = true
        private var pendingRefresh: Task<Void, Never>?
        private var keyMonitor: Any?

        init(parent: BoardCanvasView) {
            self.parent = parent
            zoom = parent.zoomScale
        }

        private var contentBounds: CGRect? {
            boardContentBounds(parent.items.map {
                (center: CGPoint(x: $0.positionX, y: $0.positionY), size: CGSize(width: $0.width, height: $0.height))
            })
        }

        private var viewportSize: CGSize {
            scrollView?.contentView.bounds.size ?? .zero
        }

        private var hasViewport: Bool {
            viewportSize.width > 0 && viewportSize.height > 0
        }

        func makeContent() -> BoardDocumentContentView {
            BoardDocumentContentView(
                project: parent.project,
                items: parent.items,
                connectors: parent.connectors,
                extent: extent,
                zoomScale: parent.$zoomScale,
                zoomAnchor: parent.$zoomAnchor,
                selectedItemIDs: parent.$selectedItemIDs,
                editingItemID: parent.$editingItemID,
                selectedConnectorID: parent.$selectedConnectorID,
                itemMenuActions: parent.itemMenuActions
            )
        }

        func attach(to scrollView: NSScrollView) {
            self.scrollView = scrollView
            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            clipView.postsFrameChangedNotifications = true
            let center = NotificationCenter.default
            center.addObserver(
                self, selector: #selector(liveScrollWillStart),
                name: NSScrollView.willStartLiveScrollNotification, object: scrollView
            )
            center.addObserver(
                self, selector: #selector(liveScrollDidEnd),
                name: NSScrollView.didEndLiveScrollNotification, object: scrollView
            )
            center.addObserver(
                self, selector: #selector(clipBoundsDidChange),
                name: NSView.boundsDidChangeNotification, object: clipView
            )
            center.addObserver(
                self, selector: #selector(viewportDidResize),
                name: NSView.frameDidChangeNotification, object: clipView
            )
        }

        // MARK: - Layout entry points

        func applyZoom(_ newZoom: CGFloat, anchor: CGPoint?) {
            let visible = currentVisibleRect()
            let anchorPoint = anchor ?? CGPoint(x: visible.midX, y: visible.midY)
            applyLayout(
                zoom: newZoom,
                visibleOrigin: zoomedVisibleOrigin(anchor: anchorPoint, visibleRect: visible, oldZoom: zoom, newZoom: newZoom),
                isRoutine: false
            )
        }

        /// Re-derives the extent for the current content and visible rect.
        /// Mid live-scroll, only refreshes the rendered content (new items) and
        /// leaves the extent alone until the scroll ends. `isRoutine` is true
        /// for the re-render SwiftUI does on every hover move: those passes may
        /// grow the extent but never shrink it (see nextCanvasExtent).
        func refreshExtent(isRoutine: Bool = true) {
            if needsInitialCentering {
                centerOnContentIfPossible()
            } else if isLiveScrolling {
                updateContent()
            } else {
                applyLayout(zoom: zoom, visibleOrigin: currentVisibleRect().origin, isRoutine: isRoutine)
            }
        }

        func zoomToFit() {
            guard let contentBounds, hasViewport else { return }
            let fit = fitToContent(contentBounds, viewportSize: viewportSize)
            parent.zoomScale = fit.zoom
            applyLayout(zoom: fit.zoom, visibleOrigin: fit.visibleOrigin, isRoutine: false)
        }

        func visibleCenter() -> CGPoint {
            let visible = currentVisibleRect()
            return CGPoint(x: visible.midX, y: visible.midY)
        }

        /// ⌘+scroll: zooms around the board point under the cursor.
        func zoomFromScroll(_ event: NSEvent) {
            guard let hostingView = scrollView?.documentView else { return }
            let newZoom = scrollWheelZoom(
                current: zoom,
                deltaY: event.scrollingDeltaY,
                hasPreciseDeltas: event.hasPreciseScrollingDeltas
            )
            guard newZoom != zoom else { return }
            // NSHostingView is flipped, so this is already the visual (top-left origin) point.
            let visualPoint = hostingView.convert(event.locationInWindow, from: nil)
            let anchor = boardPoint(fromVisual: visualPoint, zoom: zoom, extentOrigin: extent.origin)
            parent.zoomScale = newZoom
            applyZoom(newZoom, anchor: anchor)
        }

        // MARK: - Delete key

        /// A local monitor rather than .onDeleteCommand: the board's hosting
        /// view sits inside an NSScrollView and is rarely first responder, so a
        /// responder-chain command never reaches it. Text editing keeps the key:
        /// any NSText first responder (field editors, TextEditor's text view)
        /// wins, so typing in a note, a container title or the sidebar is safe.
        func installDeleteKeyMonitor() {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      [51, 117].contains(event.keyCode), // delete, forward delete
                      event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
                      let window = event.window, window === scrollView?.window,
                      !(window.firstResponder is NSText),
                      parent.onDeleteKey()
                else { return event }
                return nil
            }
        }

        func removeDeleteKeyMonitor() {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
            keyMonitor = nil
        }

        // MARK: - Private

        private func centerOnContentIfPossible() {
            guard hasViewport else {
                updateContent()
                return
            }
            needsInitialCentering = false
            let center = contentBounds.map { CGPoint(x: $0.midX, y: $0.midY) } ?? .zero
            applyLayout(
                zoom: zoom,
                visibleOrigin: centeredVisibleOrigin(on: center, viewportSize: viewportSize, zoom: zoom),
                isRoutine: false
            )
        }

        private func currentVisibleRect() -> CGRect {
            visibleBoardRect(
                scrollOrigin: scrollView?.contentView.bounds.origin ?? .zero,
                viewportSize: viewportSize,
                zoom: zoom,
                extentOrigin: extent.origin
            )
        }

        private func updateContent() {
            (scrollView?.documentView as? NSHostingView<BoardDocumentContentView>)?.rootView = makeContent()
        }

        /// The single place that sizes the hosting view and positions the
        /// scroll origin: puts `visibleOrigin` (board space) at the viewport's
        /// top-left at `newZoom`, around a freshly computed extent. A routine
        /// pass never shrinks the extent and defers origin shifts while the
        /// mouse button is down (a drag or marquee may be live); deliberate
        /// passes (zoom, centering, fit, scroll end, resize) apply as computed.
        private func applyLayout(zoom newZoom: CGFloat, visibleOrigin: CGPoint, isRoutine: Bool) {
            zoom = newZoom
            guard let scrollView, let hostingView = scrollView.documentView as? NSHostingView<BoardDocumentContentView>,
                  hasViewport
            else {
                updateContent()
                return
            }
            isApplyingLayout = true
            defer { isApplyingLayout = false }

            let visible = CGRect(
                origin: visibleOrigin,
                size: CGSize(width: viewportSize.width / newZoom, height: viewportSize.height / newZoom)
            )
            let proposed = canvasExtent(contentBounds: contentBounds, visibleRect: visible)
            guard let next = nextCanvasExtent(
                current: extent,
                proposed: proposed,
                allowShrink: !isRoutine,
                isPointerDown: isRoutine && NSEvent.pressedMouseButtons != 0
            ) else {
                updateContent()
                return
            }
            extent = next
            let frameSize = CGSize(width: extent.width * newZoom, height: extent.height * newZoom)
            if hostingView.frame.size != frameSize {
                hostingView.frame = CGRect(origin: .zero, size: frameSize)
            }
            hostingView.rootView = makeContent()

            let target = scrollOrigin(forVisibleOrigin: visibleOrigin, zoom: newZoom, extentOrigin: extent.origin)
            let current = scrollView.contentView.bounds.origin
            if abs(current.x - target.x) > 0.01 || abs(current.y - target.y) > 0.01 {
                scrollView.contentView.scroll(to: target)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

        // MARK: - Notifications

        @objc private func liveScrollWillStart(_: Notification) {
            isLiveScrolling = true
            pendingRefresh?.cancel()
        }

        @objc private func liveScrollDidEnd(_: Notification) {
            isLiveScrolling = false
            refreshExtent(isRoutine: false)
        }

        /// Discrete mouse-wheel scrolling doesn't post live-scroll
        /// notifications; shrink the stale extent once the wheel goes quiet.
        @objc private func clipBoundsDidChange(_: Notification) {
            guard !isApplyingLayout, !isLiveScrolling else { return }
            pendingRefresh?.cancel()
            pendingRefresh = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                self?.refreshExtent(isRoutine: false)
            }
        }

        @objc private func viewportDidResize(_: Notification) {
            guard !isApplyingLayout else { return }
            refreshExtent(isRoutine: false)
        }
    }
}

/// Diverts ⌘+scroll to zooming; every other scroll pans as usual. The choice
/// is made once per gesture (at its first event) and kept for its momentum,
/// so pressing ⌘ mid-pan never swallows the end phase NSScrollView needs to
/// post didEndLiveScroll.
final class BoardScrollView: NSScrollView {
    var onCommandScroll: ((NSEvent) -> Void)?
    private var isZoomGesture = false

    override func scrollWheel(with event: NSEvent) {
        let isPhaseless = event.phase.isEmpty && event.momentumPhase.isEmpty
        if isPhaseless || !event.phase.isDisjoint(with: [.mayBegin, .began]) {
            isZoomGesture = event.modifierFlags.contains(.command)
        }
        if isZoomGesture {
            onCommandScroll?(event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
