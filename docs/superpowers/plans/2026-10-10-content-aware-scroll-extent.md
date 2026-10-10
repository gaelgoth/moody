# Content-Aware Canvas Scroll Extent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> On approval, first copy this file to `docs/superpowers/plans/2026-10-10-content-aware-scroll-extent.md` (the repo's plan location per CLAUDE.md).
> **No commit steps:** the user commits their own work. Never run `git add` / `git commit`.

**Goal:** Board scroll bars cover only the photos plus a margin (not a fixed 20000×20000 void), boards open centered on their photos, and a Zoom to Fit command frames all photos.

**Architecture:** Board ("logical") coordinates become unbounded; stored `positionX/Y` are untouched (legacy boards around (10000, 10000) keep working). `BoardCanvasView`'s coordinator computes an `extent` rect in board coordinates = `union(contentBounds ± 0.5·viewport, currentVisibleRect)` and sizes the hosting view to `extent.size * zoom`. Content is rendered shifted by `−extent.origin`. Whenever the extent origin moves, the scroll origin is moved by the same amount × zoom in the same pass, so nothing jumps on screen. All math lives in pure, unit-tested free functions (`CanvasExtent.swift`). This follows the `BoardSelectionGeometry` / `ImportGeometry` pattern.

**Tech Stack:** SwiftUI + AppKit (`NSScrollView`, `NSHostingView`), Swift Testing.

**Spec:** No separate spec file. The design (approach A) was agreed in the brainstorming conversation: content + margin extent, center the content on open, Zoom to Fit command. The decisions are recorded in this plan.

## Global Constraints

- macOS 27 / Xcode 27; `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (don't add `nonisolated` to the new geometry functions; existing geometry files don't use it either).
- Keep both CLAUDE.md canvas invariants:
  - Zoom stays SwiftUI `.scaleEffect`; never `allowsMagnification`.
  - No `@Model` writes mid-gesture.
- Margin around content = **0.5 × viewport** on each side (`marginFraction: 0.5`). Why half and not a full viewport: with a full viewport of margin, scrolling to the extreme puts the content just off-screen, which is exactly the "lost" state we're fixing. With half, at least half the window still shows content at the extreme.
- Lint must pass: `swiftformat --lint .` and `swiftlint lint --strict` (140 cols, mandatory trailing commas, `@testable import` last).
- New `.swift` files are picked up automatically (file-system-synchronized groups); no pbxproj edits.

## Review Focus

1. **Pinch-zoom with a stationary cursor** (no hover events between ticks): the board point under the cursor must stay under it across many ticks. `zoomAnchor` is changing from document-view coords to board coords to fix this. Pinned by `repeatedZoomTicksKeepAnchorFixedOnScreen` (Task 1).
2. **Extent origin shifts left/up** (photo dragged above/left of everything, or the stale area dropped after scrolling back): the viewport must not jump. Pinned by `visibleOriginSurvivesExtentOriginShift` (Task 1) plus manual QA (Task 2).
3. **Trackpad momentum / elastic bounce at the extent edge**: no jitter. The extent only shrinks after `didEndLiveScroll`, never mid-scroll. Manual QA (Task 2).
4. **Legacy boards with photos near (10000, 10000), and switching boards in the sidebar**: each board opens centered on its photos. Pinned by `centeringOnLegacyContentPutsItMidViewport` (Task 1) and the `.id(project.id)` fix (Task 3).
5. **Empty board**: the extent equals the viewport (no scrolling), and a drop anywhere visible lands where released. Pinned by `emptyBoardExtentIsTheVisibleRect` (Task 1) plus manual QA.

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `moody/Views/CanvasExtent.swift` | Create | Pure geometry: content bounds, extent, the visible↔scroll↔board conversions, zoom anchoring, centering, fit. `BoardZoom` limits. |
| `moodyTests/CanvasExtentTests.swift` | Create | Swift Testing coverage for the above. |
| `moody/Views/BoardCanvasView.swift` | Rewrite | Coordinator owns the extent, zoom, and scroll observers; applies layouts; exposes Zoom to Fit. |
| `moody/Views/BoardDocumentContentView.swift` | Modify | Render in an `extent` frame; convert board↔local/visual with `extent.origin`; zoom limits from `BoardZoom`. |
| `moody/Views/BoardItemView.swift` | Modify | Add a `canvasOrigin` offset to its `.position`. |
| `moody/Views/BoardView.swift` | Modify | `zoomAnchor: CGPoint?` (board coords); `BoardCanvasController`; Zoom to Fit toolbar button (⌘0). |
| `moody/Views/RootView.swift` | Modify | `.id(project.id)` on `BoardView` so each board gets fresh canvas state. |
| `CLAUDE.md` | Modify | Replace the "fixed 20000×20000 document" description. |

---

### Task 1: Canvas extent geometry (pure, TDD)

**Files:**
- Create: `moody/Views/CanvasExtent.swift`
- Test: `moodyTests/CanvasExtentTests.swift`

**Interfaces — Produces:**
```swift
enum BoardZoom { static let minScale: CGFloat; static let maxScale: CGFloat }   // 0.1, 4
func boardContentBounds(_ items: [(center: CGPoint, size: CGSize)]) -> CGRect?
func canvasExtent(contentBounds: CGRect?, visibleRect: CGRect, marginFraction: CGFloat = 0.5) -> CGRect
func visibleBoardRect(scrollOrigin: CGPoint, viewportSize: CGSize, zoom: CGFloat, extentOrigin: CGPoint) -> CGRect
func scrollOrigin(forVisibleOrigin visibleOrigin: CGPoint, zoom: CGFloat, extentOrigin: CGPoint) -> CGPoint
func boardPoint(fromVisual visualPoint: CGPoint, zoom: CGFloat, extentOrigin: CGPoint) -> CGPoint
func zoomedVisibleOrigin(anchor: CGPoint, visibleRect: CGRect, oldZoom: CGFloat, newZoom: CGFloat) -> CGPoint
func centeredVisibleOrigin(on center: CGPoint, viewportSize: CGSize, zoom: CGFloat) -> CGPoint
func fitToContent(_ contentBounds: CGRect, viewportSize: CGSize, padding: CGFloat = 40) -> (zoom: CGFloat, visibleOrigin: CGPoint)
```

- [ ] **Step 1: Write the failing tests** in `moodyTests/CanvasExtentTests.swift`:

```swift
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
        let visible = visibleBoardRect(scrollOrigin: CGPoint(x: 300, y: 200), viewportSize: viewport, zoom: 1.5, extentOrigin: oldExtentOrigin)
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

    @Test func centeringOnLegacyContentPutsItMidViewport() {
        // Boards created before this change store positions around the old 20000x20000 document's center.
        let content = boardContentBounds([(center: CGPoint(x: 10000, y: 10000), size: CGSize(width: 320, height: 240))])!
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
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/CanvasExtentTests`
Expected: build failure ("cannot find 'boardContentBounds' in scope", etc.).

- [ ] **Step 3: Implement** `moody/Views/CanvasExtent.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: same command as Step 2. Expected: all `CanvasExtentTests` pass.

- [ ] **Step 5: Lint**: `swiftformat --lint . && swiftlint lint --strict`. Fix anything reported (`swiftformat .` auto-fixes formatting).

---

### Task 2: Wire the extent into the canvas and the content view

**Files:**
- Rewrite: `moody/Views/BoardCanvasView.swift`
- Modify: `moody/Views/BoardDocumentContentView.swift`, `moody/Views/BoardItemView.swift`, `moody/Views/BoardView.swift`, `CLAUDE.md`

**Interfaces:**
- Consumes: everything from Task 1.
- Produces:
  - `BoardCanvasController` (a class with `var zoomToFit: () -> Void`).
  - `BoardCanvasView(project:items:zoomScale:zoomAnchor:controller:)` where `zoomAnchor: Binding<CGPoint?>` is in **board** coords.
  - `BoardDocumentContentView(project:items:extent:zoomScale:zoomAnchor:)`.
  - `BoardItemView(item:canvasOrigin:isSelected:liveTranslation:onDragChanged:onDragEnded:)`.

These files compile only together, so this task is one unit. NSScrollView behavior is verified manually; the math was pinned in Task 1.

- [ ] **Step 1: `BoardItemView`.** Add `let canvasOrigin: CGPoint` after `item`, with the doc comment `/// Board-space point at the top-left of the canvas's current extent; subtracted so board coordinates map to the parent's local layout space.` Change `.position` to:

```swift
.position(
    x: item.positionX + liveTranslation.width - canvasOrigin.x,
    y: item.positionY + liveTranslation.height - canvasOrigin.y
)
```

- [ ] **Step 2: `BoardDocumentContentView`.**
  - Replace `let documentSize: CGSize` with `let extent: CGRect` (doc comment: `/// Board-space rect this view renders, decided by BoardCanvasView; its origin maps to this view's (0, 0).`).
  - Change `@Binding var zoomAnchor: CGPoint` to `@Binding var zoomAnchor: CGPoint?`.
  - Delete `minZoom` / `maxZoom` and use `BoardZoom.minScale` / `BoardZoom.maxScale` in `magnificationGesture`.
  - Pass `canvasOrigin: extent.origin` to `BoardItemView`.
  - Inner `.frame(width: extent.width, height: extent.height)`. Outer frame: `width: extent.width * zoomScale, height: extent.height * zoomScale`.
  - Hover: `let point = logicalPoint(from: point)`, then `zoomAnchor = point` and `hoveredItemID = topmostItem(at: point)?.id` (`zoomAnchor` is now board space).
  - `logicalPoint(from:)` becomes `boardPoint(fromVisual: visualPoint, zoom: zoomScale, extentOrigin: extent.origin)`. Update its doc comment: it now also adds the extent origin.
  - Marquee gesture (local coords are extent-relative): build the rect in board space:

    ```swift
    let start = CGPoint(x: value.startLocation.x + extent.minX, y: value.startLocation.y + extent.minY)
    let end = CGPoint(x: value.location.x + extent.minX, y: value.location.y + extent.minY)
    let rect = CGRect(
        x: min(start.x, end.x),
        y: min(start.y, end.y),
        width: abs(end.x - start.x),
        height: abs(end.y - start.y)
    )
    ```
    Extend the gesture's existing doc comment: "…already arrive in this ZStack's local space, which is board space minus extent.origin; add the origin, but don't run them through logicalPoint(from:)…".
  - `marqueeOverlay`: `.position(x: rect.midX - extent.minX, y: rect.midY - extent.minY)` (`marqueeRect` stays in board space).
  - Update the file header: "fixed LOGICAL size (documentSize)" becomes "laid out at extent.size, with board coordinates shifted by −extent.origin".

- [ ] **Step 3: Rewrite `BoardCanvasView.swift`:**

```swift
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
//
//  The scrollable area is content-aware, not a fixed document: the
//  coordinator keeps an `extent` (board space) = the photos' bounds padded by
//  half a viewport, unioned with whatever is on screen right now, and sizes
//  the hosting view to extent.size * zoom. Every layout pass that moves
//  extent.origin also moves the scroll origin by the same amount, so the
//  view never jumps. The extent is never shrunk during a live (trackpad /
//  scroller) scroll — that would fight momentum and elastic bounce — only
//  when it ends, or 250 ms after the last discrete wheel tick. See
//  CanvasExtent.swift for the math.
//

import AppKit
import SwiftUI

/// Lets BoardView's toolbar trigger canvas actions that need the live
/// NSScrollView (viewport size, scroll position), which only
/// BoardCanvasView's coordinator owns.
final class BoardCanvasController {
    var zoomToFit: () -> Void = {}
}

struct BoardCanvasView: NSViewRepresentable {
    let project: Project
    let items: [BoardItem]
    @Binding var zoomScale: CGFloat
    /// Board-space point to keep under the cursor while zooming; nil = viewport center.
    @Binding var zoomAnchor: CGPoint?
    let controller: BoardCanvasController

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        coordinator.parent = self
        let scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.documentView = NSHostingView(rootView: coordinator.makeContent())
        coordinator.attach(to: scrollView)
        controller.zoomToFit = { [weak coordinator] in coordinator?.zoomToFit() }
        return scrollView
    }

    func updateNSView(_: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if zoomScale != coordinator.zoom {
            coordinator.applyZoom(zoomScale, anchor: zoomAnchor)
        } else {
            coordinator.refreshExtent()
        }
    }

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
                extent: extent,
                zoomScale: parent.$zoomScale,
                zoomAnchor: parent.$zoomAnchor
            )
        }

        func attach(to scrollView: NSScrollView) {
            self.scrollView = scrollView
            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            clipView.postsFrameChangedNotifications = true
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(liveScrollWillStart), name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
            center.addObserver(self, selector: #selector(liveScrollDidEnd), name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
            center.addObserver(self, selector: #selector(clipBoundsDidChange), name: NSView.boundsDidChangeNotification, object: clipView)
            center.addObserver(self, selector: #selector(viewportDidResize), name: NSView.frameDidChangeNotification, object: clipView)
        }

        // MARK: - Layout entry points

        func applyZoom(_ newZoom: CGFloat, anchor: CGPoint?) {
            let visible = currentVisibleRect()
            let anchorPoint = anchor ?? CGPoint(x: visible.midX, y: visible.midY)
            applyLayout(zoom: newZoom, visibleOrigin: zoomedVisibleOrigin(anchor: anchorPoint, visibleRect: visible, oldZoom: zoom, newZoom: newZoom))
        }

        /// Re-derives the extent for the current content and visible rect.
        /// Mid live-scroll, only refreshes the rendered content (new items) and
        /// leaves the extent alone until the scroll ends.
        func refreshExtent() {
            if needsInitialCentering {
                centerOnContentIfPossible()
            } else if isLiveScrolling {
                updateContent()
            } else {
                applyLayout(zoom: zoom, visibleOrigin: currentVisibleRect().origin)
            }
        }

        func zoomToFit() {
            guard let contentBounds, hasViewport else { return }
            let fit = fitToContent(contentBounds, viewportSize: viewportSize)
            parent.zoomScale = fit.zoom
            applyLayout(zoom: fit.zoom, visibleOrigin: fit.visibleOrigin)
        }

        // MARK: - Private

        private func centerOnContentIfPossible() {
            guard hasViewport else {
                updateContent()
                return
            }
            needsInitialCentering = false
            let center = contentBounds.map { CGPoint(x: $0.midX, y: $0.midY) } ?? .zero
            applyLayout(zoom: zoom, visibleOrigin: centeredVisibleOrigin(on: center, viewportSize: viewportSize, zoom: zoom))
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
        /// top-left at `newZoom`, around a freshly computed extent.
        private func applyLayout(zoom newZoom: CGFloat, visibleOrigin: CGPoint) {
            zoom = newZoom
            guard let scrollView, let hostingView = scrollView.documentView as? NSHostingView<BoardDocumentContentView>, hasViewport else {
                updateContent()
                return
            }
            isApplyingLayout = true
            defer { isApplyingLayout = false }

            let visible = CGRect(origin: visibleOrigin, size: CGSize(width: viewportSize.width / newZoom, height: viewportSize.height / newZoom))
            extent = canvasExtent(contentBounds: contentBounds, visibleRect: visible)
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
            refreshExtent()
        }

        /// Discrete mouse-wheel scrolling doesn't post live-scroll
        /// notifications; shrink the stale extent once the wheel goes quiet.
        @objc private func clipBoundsDidChange(_: Notification) {
            guard !isApplyingLayout, !isLiveScrolling else { return }
            pendingRefresh?.cancel()
            pendingRefresh = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                self?.refreshExtent()
            }
        }

        @objc private func viewportDidResize(_: Notification) {
            guard !isApplyingLayout else { return }
            refreshExtent()
        }
    }
}
```

Notes for the implementer:
- `updateNSView` runs on every hover move, because `zoomAnchor` is BoardView state. The same was already true for the old `rootView` reassignment. `refreshExtent` is idempotent: the extent is unchanged and the scroll tolerance check skips `scroll(to:)`, so this is cheap.
- If the 140-col limit trips on the `addObserver` lines, wrap the arguments one per line.
- If swiftlint flags `type_body_length` / `function_body_length`, move `Coordinator` into an `extension BoardCanvasView` in the same file.

- [ ] **Step 4: `BoardView`.** Replace the `zoomAnchor` state and add the controller:

```swift
@State private var zoomScale: CGFloat = 1
/// Board-space point under the cursor, kept up to date by hover so
/// pinch-zoom is anchored at the cursor. nil until the mouse first moves
/// over the board (zoom then anchors at the viewport center).
@State private var zoomAnchor: CGPoint?
@State private var canvasController = BoardCanvasController()
```
and pass `controller: canvasController` to `BoardCanvasView`. (The toolbar button comes in Task 3.)

- [ ] **Step 5: `CLAUDE.md`.** In "Canvas view stack", replace "wrapping a plain `NSScrollView` whose documentView is an `NSHostingView` of a fixed 20000×20000 document" with: "wrapping a plain `NSScrollView` whose documentView is an `NSHostingView` sized to a content-aware `extent` (photos' bounds ± half a viewport, unioned with the visible rect; see `CanvasExtent.swift`). Board coordinates are unbounded; the content view renders them shifted by `−extent.origin`." In invariant 1, replace "resizes the hosting frame to `documentSize * zoomScale`" with "resizes the hosting frame to `extent.size * zoomScale`". Add `CanvasExtent` to the list of testable logic files at the end of the section.

- [ ] **Step 6: Build, test, and lint**
  - `xcodebuild build -project moody.xcodeproj -scheme moody -destination 'platform=macOS'`
  - `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS'`
  - `swiftformat --lint . && swiftlint lint --strict`

  Expected: build succeeds, all tests pass, no lint violations.

- [ ] **Step 7: Manual QA.** Run the app via the `run` skill or Xcode on a board with 3+ photos spread out.
  1. The board opens with the photos centered. The scroller knobs are large, not slivers.
  2. Scroll to every edge with the trackpad, including momentum and an elastic bounce. Content is always partly on screen, and there's no jitter at the edges.
  3. Scroll with a mouse wheel (if available) away from the content and back. Within ~¼ s of stopping, the stale empty area disappears with no visible jump.
  4. Drag a photo far up-left past the edge and release. The photo stays where released, the view doesn't jump, and the scrollers now reach it.
  5. Pinch-zoom in and out with the cursor held still over a photo. The photo stays under the cursor.
  6. Marquee-select at zoom ≠ 1 after the extent has shifted. The right items are selected and the rectangle tracks the cursor.
  7. Drop an image on an empty board and near the edge of a populated board. Each lands where dropped.
  8. Resize the window. Nothing jumps; the extent follows.

---

### Task 3: Zoom to Fit command and per-board canvas identity

**Files:**
- Modify: `moody/Views/BoardView.swift`, `moody/Views/RootView.swift`, `CLAUDE.md`

**Interfaces — Consumes:** `BoardCanvasController.zoomToFit` (Task 2).

- [ ] **Step 1: Toolbar button in `BoardView.body`:**

```swift
BoardCanvasView(project: project, items: items, zoomScale: $zoomScale, zoomAnchor: $zoomAnchor, controller: canvasController)
    .navigationTitle(project.name)
    .toolbar {
        ToolbarItem(placement: .primaryAction) {
            Button("Zoom to Fit", systemImage: "arrow.up.left.and.arrow.down.right") {
                canvasController.zoomToFit()
            }
            .keyboardShortcut("0", modifiers: .command)
            .help("Zoom to Fit (⌘0)")
            .disabled(items.isEmpty)
        }
    }
```

- [ ] **Step 2: Per-board identity in `RootView.detail`:** change `BoardView(project: project)` to

```swift
BoardView(project: project)
    // Fresh zoom/scroll/canvas state per board, so switching boards
    // re-centers on the new board's photos instead of inheriting the old
    // board's coordinator and scroll position.
    .id(project.id)
```

- [ ] **Step 3: CLAUDE.md.** Add one sentence to the canvas section: "`BoardView`'s toolbar has Zoom to Fit (⌘0), which goes through `BoardCanvasController`, since only the canvas coordinator knows the viewport."

- [ ] **Step 4: Build, test, and lint** with the same three commands as Task 2 Step 6. Expected: all green.

- [ ] **Step 5: Manual QA**
  1. Zoom to Fit (button and ⌘0) on a spread-out board frames every photo with a small padding.
  2. On a board with a single small photo, it centers at 100% instead of magnifying.
  3. The button is disabled on an empty board.
  4. Switch between two boards in the sidebar. Each opens centered on its own photos at 100%.
  5. Sidebar rename (Return / double-click) still works; it's a `List` focus path, so check that ⌘0 didn't interfere.

---

## Verification (end-to-end)

1. `swiftformat --lint . && swiftlint lint --strict`: clean.
2. `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS'`: all unit and UI tests pass, including the new `CanvasExtentTests`.
3. Manual QA checklists from Task 2 Step 7 and Task 3 Step 5 on a real board, plus one legacy board created before this change (photos near (10000, 10000)).
