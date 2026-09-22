# Board Multi-Select Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user drag a rectangle over empty canvas to select multiple board items at once (like a desktop Finder rubber-band select), then drag any selected item to move the whole group together.

**Architecture:** Selection and live drag-translation state move up from `BoardItemView` (which today owns them locally) to `BoardDocumentContentView` (which already owns the analogous `draggingItemID`/`hoveredItemID` state). A `DragGesture` attached to a new background layer inside the canvas's `ZStack` — *before* `.scaleEffect` is applied — recognizes marquee drags in logical/document coordinates and live-highlights intersecting items. `BoardItemView`'s own drag gesture stops writing to the model itself; it now just reports translation up via closures, and the parent decides whether one item or the whole selected group should move, committing the position/z-index writes once, in a single `.onEnded`.

**Tech Stack:** Swift, SwiftUI, AppKit (macOS-only target), SwiftData, Swift Testing (`#expect`).

**Spec:** N/A — this is a bounded-path change (an extension of an existing interaction flow, not a new subsystem), so per the brainstorming skill no separate spec doc was written. The agreed design is captured in this plan's Context and Global Constraints.

## Context

The board canvas (`BoardCanvasView` → `BoardDocumentContentView` → `BoardItemView`) currently supports dragging exactly one image at a time; there's no way to select or move several images as a group. The user wants desktop-style multi-select: click-and-slide over empty canvas to select a group, then drag to move them together.

Two rounds of codebase research (an Explore pass over the whole view/model/storage layer, then a Plan pass that read every relevant file in full and verified SwiftUI gesture-precedence semantics against Apple's docs) surfaced one load-bearing constraint that shapes this whole design: **`BoardItemView.swift`'s header comment documents that SwiftData `@Model` writes (`item.positionX`, `item.zIndex`) must happen only once a drag gesture ends, never mid-gesture** — a mid-gesture write can reassign the hosting `NSHostingView`'s `rootView` (because `zIndex` feeds a `@Query` sort key) and silently kill the in-flight AppKit mouse-tracking loop, canceling the drag. Every piece of new state below is designed to respect that: plain `@State` mutates freely during `.onChanged` (exactly like the existing `dragOffset` pattern already does), and the only `@Model` write is the single `commitGroupMove` + `save()` call inside `.onEnded`.

The other key finding: the marquee-select gesture must be attached to a view *inside* the `ZStack`'s `.scaleEffect`, not to the outer container (where `magnificationGesture`/`onContinuousHover`/`onDrop` already live). The outer container's points are in *post-scale* view space and need `logicalPoint(from:)` to convert back to document coordinates; a gesture attached *inside* the scale already receives points in document space directly. Reusing `logicalPoint(from:)` for a gesture attached inside the scale would silently double-convert — correct-looking at `zoomScale == 1.0`, silently wrong at any other zoom level. This plan avoids that class of bug by construction rather than by comment.

## Global Constraints

- **Platform:** macOS only (confirmed: `SDKROOT = macosx`, no iOS target). AppKit APIs are fully available and already used directly.
- **No new SwiftData model fields.** Selection is ephemeral UI state, never persisted — it resets when a board is reopened. `moody/Models/BoardItem.swift` is not modified.
- **`@Model` writes only in `.onEnded`, never `.onChanged`** — see Context above. This applies to every gesture handler touched in this plan.
- **Multi-select is triggered only by:** (a) dragging a rectangle over empty canvas (marquee select, live-highlighting as it's dragged), or (b) a plain click (no movement) on a single item, which selects just that item and clears any existing multi-selection. **No shift-click / cmd-click toggle-select** in this pass.
- **Dragging an item that is NOT in the current selection** clears the selection and drags just that single item (standard Finder-like behavior).
- **No Delete/Backspace key support** in this pass — select + move only.
- **Xcode scheme:** `moody` (project `moody.xcodeproj`, targets `moody`/`moodyTests`/`moodyUITests`).

---

### Task 1: Marquee rect-intersection geometry (pure function)

**Files:**
- Create: `moody/Views/BoardSelectionGeometry.swift`
- Test: `moodyTests/BoardSelectionGeometryTests.swift`

**Interfaces:**
- Produces: `func itemsIntersecting(_ marqueeRect: CGRect, items: [(id: UUID, center: CGPoint, size: CGSize)]) -> Set<UUID>` — used by Task 3's marquee gesture handler.

- [ ] **Step 1: Write the failing tests**

Create `moodyTests/BoardSelectionGeometryTests.swift`:

```swift
//
//  BoardSelectionGeometryTests.swift
//  moodyTests
//

import Testing
import Foundation
@testable import moody

struct BoardSelectionGeometryTests {

    @Test func fullyOverlappingItemIsSelected() {
        let marquee = CGRect(x: 0, y: 0, width: 200, height: 200)
        let items = [(id: UUID(), center: CGPoint(x: 100, y: 100), size: CGSize(width: 40, height: 40))]
        let result = itemsIntersecting(marquee, items: items)
        #expect(result == Set(items.map(\.id)))
    }

    @Test func partiallyOverlappingItemIsSelected() {
        let marquee = CGRect(x: 0, y: 0, width: 100, height: 100)
        let id = UUID()
        // item rect spans x 70...110, y 70...110 — overlaps the marquee's
        // bottom-right corner without being fully contained by it.
        let items = [(id: id, center: CGPoint(x: 90, y: 90), size: CGSize(width: 40, height: 40))]
        let result = itemsIntersecting(marquee, items: items)
        #expect(result == [id])
    }

    @Test func nonOverlappingItemIsExcluded() {
        let marquee = CGRect(x: 0, y: 0, width: 50, height: 50)
        let items = [(id: UUID(), center: CGPoint(x: 500, y: 500), size: CGSize(width: 40, height: 40))]
        let result = itemsIntersecting(marquee, items: items)
        #expect(result.isEmpty)
    }

    @Test func zeroSizeMarqueeRectSelectsNothingEvenCenteredOnAnItem() {
        let center = CGPoint(x: 100, y: 100)
        let marquee = CGRect(x: center.x, y: center.y, width: 0, height: 0)
        let items = [(id: UUID(), center: center, size: CGSize(width: 40, height: 40))]
        let result = itemsIntersecting(marquee, items: items)
        #expect(result.isEmpty)
    }

    @Test func emptyItemsListReturnsEmptySet() {
        let marquee = CGRect(x: 0, y: 0, width: 100, height: 100)
        let result = itemsIntersecting(marquee, items: [])
        #expect(result.isEmpty)
    }

    @Test func multipleOverlappingItemsAllReturned() {
        let marquee = CGRect(x: 0, y: 0, width: 200, height: 200)
        let idA = UUID()
        let idB = UUID()
        let idOutside = UUID()
        let items = [
            (id: idA, center: CGPoint(x: 50, y: 50), size: CGSize(width: 20, height: 20)),
            (id: idB, center: CGPoint(x: 150, y: 150), size: CGSize(width: 20, height: 20)),
            (id: idOutside, center: CGPoint(x: 1000, y: 1000), size: CGSize(width: 20, height: 20))
        ]
        let result = itemsIntersecting(marquee, items: items)
        #expect(result == [idA, idB])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail (compile error — function doesn't exist yet)**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/BoardSelectionGeometryTests`
Expected: FAIL to build — `itemsIntersecting` is undefined.

- [ ] **Step 3: Write the implementation**

Create `moody/Views/BoardSelectionGeometry.swift`:

```swift
//
//  BoardSelectionGeometry.swift
//  moody
//
//  Pure geometry for marquee (rubber-band) multi-select on the board canvas.
//

import Foundation

/// Ids of items whose bounding rect (center ± size/2) intersects `marqueeRect`.
/// Uses ordinary rect intersection ("any overlap selects", matching Finder's
/// rubber-band semantics — not full containment). A zero-size marqueeRect
/// (e.g. a plain click) never intersects anything, which is what makes
/// "click empty canvas clears selection" work with no special-casing.
func itemsIntersecting(
    _ marqueeRect: CGRect,
    items: [(id: UUID, center: CGPoint, size: CGSize)]
) -> Set<UUID> {
    Set(items.compactMap { item in
        let rect = CGRect(
            x: item.center.x - item.size.width / 2,
            y: item.center.y - item.size.height / 2,
            width: item.size.width,
            height: item.size.height
        )
        return rect.intersects(marqueeRect) ? item.id : nil
    })
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/BoardSelectionGeometryTests`
Expected: PASS (all 6 tests).

Leave the changes uncommitted — the user stages and commits their own work.

---

### Task 2: Group-move commit function (model-level)

**Files:**
- Create: `moody/Views/BoardGroupMove.swift`
- Test: `moodyTests/BoardGroupMoveTests.swift`

**Interfaces:**
- Consumes: `nextZIndex(existing: [Int]) -> Int` from `moody/Import/ImportGeometry.swift` (existing, unchanged).
- Produces: `func commitGroupMove(movingItems: [BoardItem], allZIndices: [Int], translation: CGSize)` — used by Task 3's `handleItemDragEnded`.

- [ ] **Step 1: Write the failing tests**

Create `moodyTests/BoardGroupMoveTests.swift`:

```swift
//
//  BoardGroupMoveTests.swift
//  moodyTests
//

import Testing
import SwiftData
import Foundation
@testable import moody

struct BoardGroupMoveTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Project.self, BoardItem.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    @Test func shiftsPositionOfEveryMovingItem() throws {
        let context = try makeContext()
        let project = Project(name: "Test")
        context.insert(project)
        let a = BoardItem(fileName: "a.jpg", positionX: 10, positionY: 10, width: 40, height: 40, pixelWidth: 40, pixelHeight: 40, zIndex: 1, project: project)
        let b = BoardItem(fileName: "b.jpg", positionX: 20, positionY: 20, width: 40, height: 40, pixelWidth: 40, pixelHeight: 40, zIndex: 2, project: project)
        context.insert(a)
        context.insert(b)
        try context.save()

        commitGroupMove(movingItems: [a, b], allZIndices: [a.zIndex, b.zIndex], translation: CGSize(width: 5, height: -5))

        #expect(a.positionX == 15)
        #expect(a.positionY == 5)
        #expect(b.positionX == 25)
        #expect(b.positionY == 15)
    }

    @Test func leavesNonMovingItemsUntouched() throws {
        let context = try makeContext()
        let project = Project(name: "Test")
        context.insert(project)
        let moving = BoardItem(fileName: "a.jpg", positionX: 10, positionY: 10, width: 40, height: 40, pixelWidth: 40, pixelHeight: 40, zIndex: 1, project: project)
        let stationary = BoardItem(fileName: "b.jpg", positionX: 20, positionY: 20, width: 40, height: 40, pixelWidth: 40, pixelHeight: 40, zIndex: 2, project: project)
        context.insert(moving)
        context.insert(stationary)
        try context.save()

        commitGroupMove(movingItems: [moving], allZIndices: [moving.zIndex, stationary.zIndex], translation: CGSize(width: 5, height: 5))

        #expect(stationary.positionX == 20)
        #expect(stationary.positionY == 20)
    }

    @Test func assignsDistinctAscendingZIndicesAboveAllExisting() throws {
        let context = try makeContext()
        let project = Project(name: "Test")
        context.insert(project)
        let a = BoardItem(fileName: "a.jpg", positionX: 0, positionY: 0, width: 40, height: 40, pixelWidth: 40, pixelHeight: 40, zIndex: 1, project: project)
        let b = BoardItem(fileName: "b.jpg", positionX: 0, positionY: 0, width: 40, height: 40, pixelWidth: 40, pixelHeight: 40, zIndex: 5, project: project)
        let c = BoardItem(fileName: "c.jpg", positionX: 0, positionY: 0, width: 40, height: 40, pixelWidth: 40, pixelHeight: 40, zIndex: 3, project: project)
        context.insert(a)
        context.insert(b)
        context.insert(c)
        try context.save()

        commitGroupMove(movingItems: [a, c], allZIndices: [a.zIndex, b.zIndex, c.zIndex], translation: .zero)

        #expect(a.zIndex > 5)
        #expect(c.zIndex > 5)
        #expect(a.zIndex != c.zIndex)
        #expect(b.zIndex == 5)
    }

    @Test func preservesRelativeFrontToBackOrderAmongMovingItems() throws {
        let context = try makeContext()
        let project = Project(name: "Test")
        context.insert(project)
        // c was in front of a before the move (zIndex 4 > 1).
        let a = BoardItem(fileName: "a.jpg", positionX: 0, positionY: 0, width: 40, height: 40, pixelWidth: 40, pixelHeight: 40, zIndex: 1, project: project)
        let c = BoardItem(fileName: "c.jpg", positionX: 0, positionY: 0, width: 40, height: 40, pixelWidth: 40, pixelHeight: 40, zIndex: 4, project: project)
        context.insert(a)
        context.insert(c)
        try context.save()

        commitGroupMove(movingItems: [a, c], allZIndices: [a.zIndex, c.zIndex], translation: .zero)

        #expect(c.zIndex > a.zIndex)
    }

    @Test func singleItemMovingItemsBehavesLikeSoloDragCommit() throws {
        let context = try makeContext()
        let project = Project(name: "Test")
        context.insert(project)
        let a = BoardItem(fileName: "a.jpg", positionX: 10, positionY: 10, width: 40, height: 40, pixelWidth: 40, pixelHeight: 40, zIndex: 1, project: project)
        context.insert(a)
        try context.save()

        commitGroupMove(movingItems: [a], allZIndices: [a.zIndex], translation: CGSize(width: 3, height: 4))

        #expect(a.positionX == 13)
        #expect(a.positionY == 14)
        #expect(a.zIndex == 2)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail (compile error — function doesn't exist yet)**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/BoardGroupMoveTests`
Expected: FAIL to build — `commitGroupMove` is undefined.

- [ ] **Step 3: Write the implementation**

Create `moody/Views/BoardGroupMove.swift`:

```swift
//
//  BoardGroupMove.swift
//  moody
//
//  Commits a completed drag (solo or group) to the model. Mutates
//  already-inserted @Model objects in place; the caller must call
//  modelContext.save() afterwards. Must only be invoked once a drag
//  gesture has ended, never mid-.onChanged — see BoardDocumentContentView
//  for why a mid-gesture @Model write is unsafe.
//

import Foundation

/// Shifts positionX/positionY of every item in `movingItems` by `translation`,
/// and reassigns each an ascending zIndex above every value in `allZIndices`
/// so the whole group comes to front together, preserving movingItems' own
/// relative front-to-back order. A single-item `movingItems` array is the
/// solo-drag case.
func commitGroupMove(movingItems: [BoardItem], allZIndices: [Int], translation: CGSize) {
    let ordered = movingItems.sorted { $0.zIndex < $1.zIndex }
    var nextZ = nextZIndex(existing: allZIndices)
    for item in ordered {
        item.positionX += translation.width
        item.positionY += translation.height
        item.zIndex = nextZ
        nextZ += 1
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/BoardGroupMoveTests`
Expected: PASS (all 5 tests).

Leave the changes uncommitted — the user stages and commits their own work.

---

### Task 3: Wire selection, marquee drag, and group-drag into the view layer

This task rewrites `BoardItemView.swift` and `BoardDocumentContentView.swift` together — their call site (the `BoardItemView` initializer) changes shape, so the app only compiles once both are updated. There's no automated test for SwiftUI gesture wiring in this codebase (confirmed: no existing test drives a `DragGesture` or `.onContinuousHover`); the deliverable is verified by building successfully and manually exercising every interaction listed in Step 4.

**Files:**
- Modify: `moody/Views/BoardItemView.swift` (full rewrite, current file is 79 lines)
- Modify: `moody/Views/BoardDocumentContentView.swift` (full rewrite, current file is 147 lines)

**Interfaces:**
- Consumes: `itemsIntersecting(_:items:)` from Task 1, `commitGroupMove(movingItems:allZIndices:translation:)` from Task 2.
- Produces: `BoardItemView(item: BoardItem, isSelected: Bool, liveTranslation: CGSize, onDragChanged: (CGSize) -> Void, onDragEnded: (CGSize) -> Void)` — the new initializer shape; nothing outside this task calls it (`BoardView.swift`/`BoardCanvasView.swift` only construct `BoardDocumentContentView`, not `BoardItemView` directly, so no other file needs updating).

- [ ] **Step 1: Rewrite `BoardItemView.swift`**

Replace the entire contents of `moody/Views/BoardItemView.swift` with:

```swift
//
//  BoardItemView.swift
//  moody
//
//  One placed image on a board: renders at its stored position/size, and
//  reports drag gestures up to BoardDocumentContentView, which owns
//  selection state and commits the resulting move(s) to the model — see
//  that file for why model writes must happen only once a drag ends, never
//  mid-gesture.
//
//  Cursor feedback (open/closed hand) is NOT handled here — it's centralized
//  in BoardDocumentContentView via a single continuous hover tracker, since
//  per-item .onHover proved unreliable on macOS once a .gesture() is also
//  attached to the same view (hover-exit could be missed, leaving the
//  cursor stuck).
//

import SwiftUI

struct BoardItemView: View {
    let item: BoardItem
    let isSelected: Bool
    /// Offset applied to this item's rendered position while it (or its
    /// selection group) is being dragged. Owned by the parent, not local
    /// state, so one gesture recognized on one item can move every selected
    /// sibling in lockstep.
    let liveTranslation: CGSize
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize) -> Void

    @State private var image: NSImage?

    var body: some View {
        content
            .frame(width: item.width, height: item.height)
            .overlay(selectionOverlay)
            .contentShape(Rectangle())
            .position(x: item.positionX + liveTranslation.width, y: item.positionY + liveTranslation.height)
            .gesture(dragGesture)
            .task(id: item.fileName) {
                image = ImageCache.shared.image(for: item)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .shadow(radius: 4)
        } else {
            Rectangle().fill(Color.gray.opacity(0.15))
        }
    }

    @ViewBuilder
    private var selectionOverlay: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: 3)
        }
    }

    private var dragGesture: some Gesture {
        // minimumDistance: 0 so a plain click (no movement) also fires
        // onChanged/onEnded with a zero translation — that's what makes a
        // click-without-drag select just this item (see
        // BoardDocumentContentView.handleItemDragChanged).
        DragGesture(minimumDistance: 0)
            .onChanged { value in onDragChanged(value.translation) }
            .onEnded { value in onDragEnded(value.translation) }
    }
}
```

- [ ] **Step 2: Rewrite `BoardDocumentContentView.swift`**

Replace the entire contents of `moody/Views/BoardDocumentContentView.swift` with:

```swift
//
//  BoardDocumentContentView.swift
//  moody
//
//  The fixed-size SwiftUI content hosted as an NSScrollView's documentView.
//  Laid out at a fixed LOGICAL size (documentSize) and visually scaled by
//  zoomScale via .scaleEffect — a SwiftUI-native transform, so drag
//  translations, hover tracking, and onDrop locations all stay correctly
//  aligned with what's on screen at any zoom level. (BoardCanvasView keeps
//  the hosting NSView's frame sized to documentSize * zoomScale so
//  NSScrollView's scroll bounds match the scaled rendering.)
//
//  Selection and drag state both live here, not on individual BoardItemViews:
//  a single drag gesture (recognized on whichever item is under the cursor)
//  needs to be able to move every OTHER selected item's rendered position
//  too, and the marquee-select rectangle needs to test against every item's
//  bounds. All SwiftData writes (position, and the bring-to-front zIndex
//  bump) happen only once a drag gesture ends, never mid-gesture: zIndex
//  feeds a @Query sort key, and mutating it while a drag is live can trigger
//  a re-render that reassigns the hosting NSHostingView's rootView, which
//  can intermittently kill the in-flight AppKit mouse tracking loop and
//  silently cancel the drag. Deferring writes to onEnded avoids that
//  entirely — see handleItemDragEnded/commitGroupMove.
//

import AppKit
import CoreGraphics
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BoardDocumentContentView: View {
    let project: Project
    let items: [BoardItem]
    let documentSize: CGSize
    @Binding var zoomScale: CGFloat
    @Binding var zoomAnchor: CGPoint

    @Environment(\.modelContext) private var modelContext

    /// The item a drag gesture is currently live on (tracked here, not
    /// written to the model, so the dragged item(s) render in front of their
    /// siblings instantly without a SwiftData write hitting the @Query
    /// mid-gesture — see file header).
    @State private var activeDragItemID: UUID?

    /// Live translation shared by every item in `movingItemIDs` — a group
    /// moves rigidly together, so one shared value is enough (no per-item map).
    @State private var dragTranslation: CGSize = .zero

    /// Ids of the currently multi-selected items. Ephemeral UI state, never
    /// persisted — resets whenever the board is reopened.
    @State private var selectedItemIDs: Set<UUID> = []

    /// The in-progress marquee (rubber-band) selection rectangle, in logical/
    /// document coordinates. nil when no marquee drag is in progress.
    @State private var marqueeRect: CGRect?

    /// Which item (if any) the cursor is currently over. Computed from a
    /// single continuous hover stream on this container rather than N
    /// independent per-item .onHover trackers — per-item hover exit proved
    /// unreliable on macOS once a .gesture() is also attached to the same
    /// view (the cursor could get stuck showing the open hand indefinitely
    /// after leaving an image). One source of truth avoids that entirely.
    @State private var hoveredItemID: UUID?

    /// The committed zoomScale value from just before the in-progress pinch
    /// gesture began, so each .onChanged tick can compute an absolute new
    /// zoomScale (MagnificationGesture's value is cumulative since gesture
    /// start, not incremental). Written directly into the shared zoomScale
    /// binding on every tick — not tracked separately via @GestureState —
    /// so BoardCanvasView (which resizes the NSScrollView's hosting frame
    /// off the same zoomScale) stays in sync for the whole gesture, not
    /// just once it ends. A split "live vs. committed" value was exactly
    /// the bug: BoardCanvasView only saw the committed one, so the content
    /// and the scroll frame disagreed on scale for the entire pinch.
    @State private var gestureBaseScale: CGFloat?

    private static let minZoom: CGFloat = 0.1
    private static let maxZoom: CGFloat = 4

    /// Ids of items the live drag should move: the whole selection if the
    /// dragged item is a member of a multi-item selection, otherwise just
    /// the dragged item alone.
    private var movingItemIDs: Set<UUID> {
        guard let activeDragItemID else { return [] }
        if selectedItemIDs.contains(activeDragItemID), selectedItemIDs.count > 1 {
            return selectedItemIDs
        }
        return [activeDragItemID]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(marqueeGesture)

            ForEach(items.sorted(by: { $0.zIndex < $1.zIndex })) { item in
                BoardItemView(
                    item: item,
                    isSelected: selectedItemIDs.contains(item.id),
                    liveTranslation: movingItemIDs.contains(item.id) ? dragTranslation : .zero,
                    onDragChanged: { translation in
                        handleItemDragChanged(itemID: item.id, translation: translation)
                    },
                    onDragEnded: { translation in
                        handleItemDragEnded(translation: translation)
                    }
                )
                .zIndex(movingItemIDs.contains(item.id) ? .infinity : Double(item.zIndex))
            }

            if let marqueeRect {
                marqueeOverlay(marqueeRect)
            }
        }
        .frame(width: documentSize.width, height: documentSize.height)
        .scaleEffect(zoomScale, anchor: .topLeading)
        // .scaleEffect renders bigger but does NOT change the reported
        // layout size (it stays documentSize) — without this outer frame,
        // SwiftUI would position the nominally-20000x20000 content inside
        // whatever larger size BoardCanvasView gives the hosting NSView,
        // instead of filling it from the top-left, so on-screen items would
        // land somewhere other than where onDrop/onContinuousHover (and the
        // NSScrollView's own scroll bounds) expect them to be.
        .frame(
            width: documentSize.width * zoomScale,
            height: documentSize.height * zoomScale,
            alignment: .topLeading
        )
        .contentShape(Rectangle())
        .gesture(magnificationGesture)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                zoomAnchor = point
                hoveredItemID = topmostItem(at: logicalPoint(from: point))?.id
            case .ended:
                hoveredItemID = nil
            }
            updateCursor()
        }
        .onDrop(of: [UTType.image], isTargeted: nil) { providers, location in
            let dropPoint = logicalPoint(from: location)
            Task {
                await ImageImportService.importDroppedItems(providers, into: project, at: dropPoint, context: modelContext)
            }
            return true
        }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let base = gestureBaseScale ?? zoomScale
                if gestureBaseScale == nil {
                    gestureBaseScale = base
                }
                zoomScale = min(max(base * value, Self.minZoom), Self.maxZoom)
            }
            .onEnded { _ in
                gestureBaseScale = nil
            }
    }

    /// Attached to a child INSIDE the ZStack's .scaleEffect (unlike
    /// magnification/hover/drop above, which are attached to the outer,
    /// post-scale container) — so value.location/.startLocation already
    /// arrive in logical/document coordinates. Do NOT run these through
    /// logicalPoint(from:), which is calibrated for the outer view space;
    /// reusing it here would silently double-convert, only visibly wrong at
    /// zoom levels other than 1.0.
    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let rect = CGRect(
                    x: min(value.startLocation.x, value.location.x),
                    y: min(value.startLocation.y, value.location.y),
                    width: abs(value.location.x - value.startLocation.x),
                    height: abs(value.location.y - value.startLocation.y)
                )
                marqueeRect = rect
                selectedItemIDs = itemsIntersecting(rect, items: items.map {
                    (id: $0.id, center: CGPoint(x: $0.positionX, y: $0.positionY),
                     size: CGSize(width: $0.width, height: $0.height))
                })
                updateCursor()
            }
            .onEnded { _ in
                marqueeRect = nil
                updateCursor()
            }
    }

    @ViewBuilder
    private func marqueeOverlay(_ rect: CGRect) -> some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.12))
            .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    private func handleItemDragChanged(itemID: UUID, translation: CGSize) {
        if activeDragItemID == nil {
            activeDragItemID = itemID
            if !selectedItemIDs.contains(itemID) {
                selectedItemIDs = [itemID]
            }
        }
        dragTranslation = translation
        updateCursor()
    }

    private func handleItemDragEnded(translation: CGSize) {
        let movingItems = items.filter { movingItemIDs.contains($0.id) }
        commitGroupMove(movingItems: movingItems, allZIndices: items.map(\.zIndex), translation: translation)
        try? modelContext.save()
        activeDragItemID = nil
        dragTranslation = .zero
        updateCursor()
    }

    /// onContinuousHover/onDrop report points in this view's own (post
    /// .scaleEffect + outer .frame) layout space, which now spans
    /// documentSize * zoomScale — divide back down to the logical/
    /// document units that item.positionX/Y are stored in.
    private func logicalPoint(from visualPoint: CGPoint) -> CGPoint {
        CGPoint(x: visualPoint.x / zoomScale, y: visualPoint.y / zoomScale)
    }

    private func topmostItem(at point: CGPoint) -> BoardItem? {
        items
            .filter { item in
                let rect = CGRect(
                    x: item.positionX - item.width / 2,
                    y: item.positionY - item.height / 2,
                    width: item.width,
                    height: item.height
                )
                return rect.contains(point)
            }
            .max(by: { $0.zIndex < $1.zIndex })
    }

    private func updateCursor() {
        if activeDragItemID != nil {
            NSCursor.closedHand.set()
        } else if marqueeRect != nil {
            NSCursor.arrow.set()
        } else if hoveredItemID != nil {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -project moody.xcodeproj -scheme moody -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run the full test suite**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS'`
Expected: PASS (all existing tests plus Task 1/2's new tests — nothing in this task should have broken any of them).

- [ ] **Step 5: Manually verify in the running app**

Build and run the `moody` scheme, open (or create) a project with at least 4-5 images on the board, then check every item below (per this codebase's convention of testing gesture-driven UI manually, since it isn't unit-testable here):

1. Drag a rectangle starting on empty canvas across several items — they highlight (accent-color border) live as the rectangle's edge crosses them, not just at drag-end.
2. Release the marquee drag — the highlighted items stay selected (border persists) and the marquee rectangle disappears.
3. Drag any one of the selected items — the whole selected group moves together, maintaining their relative positions.
4. Release the group drag — all moved items persist their new position (quit and relaunch, or navigate away and back, to confirm the SwiftData save landed for every item, not just the one you grabbed).
5. With a group still selected, drag an item that is NOT part of the selection — the selection clears (other items lose their border) and only the dragged item moves.
6. Click (no drag) directly on a single unselected item — it becomes the sole selection.
7. Click (no drag) on empty canvas while something is selected — the selection clears.
8. Repeat checks 1-3 at a zoom level other than 100% (pinch-zoom in/out first) — marquee selection must land on the correct items, not be offset.
9. Watch the cursor through several marquee-drag and group-drag cycles — it should never get stuck showing the open/closed hand after the mouse leaves an item or after a marquee drag ends.

Leave the changes uncommitted — the user stages and commits their own work.

---

## Verification Summary

- Tasks 1-2 are fully covered by automated Swift Testing unit tests (`xcodebuild test ... -only-testing:` per task, then the full suite in Task 3 Step 4).
- Task 3's gesture wiring has no automated coverage (consistent with the rest of this codebase's drag/hover interactions) — it's verified by the 9-point manual checklist in Task 3 Step 5, run in the actual built app.
- Do not report this feature complete until Task 3 Step 5's manual checklist has actually been run against the built app, not just inferred from the code.
