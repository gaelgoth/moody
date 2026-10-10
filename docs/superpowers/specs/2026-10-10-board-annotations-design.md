# Board Annotations — Notes, Containers, Connectors (design spec)

## Context

Today every board element is a photo. Users want to *document* a moodboard:
- **Notes** — sticky-note text cards placed on the board.
- **Containers** — a titled (icon + text) row or column that auto-stacks photos dropped into it, e.g. a "Geneva" column holding all Geneva photos, reorderable by drag.
- **Connectors** — straight lines linking notes, photos and containers that follow the elements when they move, and can be unlinked.

The board also has no way to delete anything yet; notes make that unavoidable, so Delete is part of this work.

**Success:** a user can add/edit/color/delete notes; create row/column containers, name them with an icon, drag photos in, out and reorder them, drop Finder files straight into one; connect any two elements, see the line follow live during drags, and unlink it. Existing boards open unchanged.

## Decisions (from brainstorming)

| Topic | Decision |
|---|---|
| Scope | One spec, one plan in 4 shippable phases: 0 foundation → 1 notes → 2 containers → 3 connectors |
| Note | Sticky card, `FolderColor` preset (default yellow), fixed width, height auto-fits text, no resize handle |
| Stack sizing | Photos keep their own size, stacked edge-to-edge (12pt gap), centered on the cross axis |
| Stack moves | All by drag: drop on container to add (position along axis = order), drag within to reorder, drag out to remove; Finder drops onto a container import into it |
| Stackable | Photos only (notes just sit on top) |
| Connector | Select exactly 2 → toolbar Connect / Unlink; straight edge-to-edge line, no arrowhead |
| Data model | `kind` discriminator on `BoardItem` + separate `BoardConnector` model |
| Delete | Toolbar + Delete key; confirmation alert only when the selection contains photos (file is removed, no undo) |

## Phase 0 — Foundation: kind + Delete

### Model (`moody/Models/BoardItem.swift`, new `BoardConnector.swift`)
All new fields have defaults so lightweight migration keeps working (see `Project.swift` comment); there is no `VersionedSchema`.

`BoardItem` additions:
- `kindRaw: String = "image"`, read via `kind: BoardItemKind` (`.image | .note | .container`), unknown → `.image` (same fallback idea as `resolvedIconName` in `FolderAppearance.swift`).
- Note: `text: String = ""`, `colorName: String = "yellow"` (resolved through `FolderColor`, fallback yellow).
- Container: `title: String = ""`, `iconName: String = "photo"` (resolved through `FolderIcon`), shares `colorName`, `axisRaw: String = "column"` → `axis: StackAxis` (`.row | .column`).
- Stack membership: `container: BoardItem?` with inverse `@Relationship(deleteRule: .nullify) stackedItems: [BoardItem]`, `stackOrder: Int = 0`.
- `@Relationship(deleteRule: .cascade) outgoingConnectors` / `incomingConnectors` (inverses of `BoardConnector.from` / `.to`).
- `fileName` stays non-optional; `""` for notes/containers.

`BoardConnector` (`@Model`): `id: UUID`, `from: BoardItem?`, `to: BoardItem?`, `createdAt: Date`. Add to `Schema` in `moodyApp.swift` and to every test container (`BoardGroupMoveTests`, `FolderCascadeDeleteTests`, `SidebarTreeTests`, `ProjectCascadeDeleteTests`, `ImageImportServiceTests` …). `BoardView` gains a second `@Query<BoardConnector>` filtered on `$0.from?.project?.id == projectID`. Project delete cascades items → connectors.

### Image-only paths become kind-aware
- `BoardItemView` switches on `kind` for its body; only `.image` touches `ImageCache` (its `.task` too).
- Download (`BoardView.download`) filters to `.image`; "Download Selected" label/disable counts images only.
- `topmostItem(at:)`, marquee, extent, alignment work on center+size and need no change.

### Delete
- `deleteSelection()` in `BoardView`: toolbar "Delete" button in the selection toolbar group, plus `.onDeleteCommand` on the canvas (doesn't fire while a text field/editor is first responder).
- If any selected item is `.image` → confirmation alert ("Delete N items? Photos are removed from the board and disk."); otherwise delete immediately.
- For images, also `FileStorageService().deleteFile(fileName:projectID:)` (exists, currently unused) and evict from `ImageCache`.
- Any container that lost a child is re-laid-out (phase 2 hook; no-op before).
- Clear `selectedItemIDs`, `modelContext.save()`.

## Phase 1 — Notes

- **Toolbar "Add" menu** (always visible, `plus` icon, like the sidebar's single "New" menu): Note, Row Container, Column Container (container entries arrive in phase 2).
- **Placement:** `BoardCanvasController` gains `visibleCenter: () -> CGPoint` (board coordinates), set by the coordinator like `zoomToFit`. New element is centered there with `zIndex = nextZIndex(existing:)`, selected, and (for notes) put in edit mode.
- **`NoteCardView`** (`moody/Views/Annotations/`): rounded rect filled with a pastel of the note's `FolderColor`, dark primary text, padding, small shadow. Default width 220.
- **Editing:** double-click detected in `handleItemDragEnded` when `translation == .zero` and `NSApp.currentEvent?.clickCount == 2` — no extra `TapGesture(count: 2)` (it competes with single-click selection, same lesson as the sidebar). `editingItemID` is plain `@State` in `BoardDocumentContentView`; the card swaps to a `TextEditor` bound to a local draft. Commit on focus loss / Esc: write `text`, set `height = noteHeight(text:width:)`, save. This is a commit outside any gesture (invariant 2 holds).
- **`noteHeight(text:width:) -> CGFloat`** (pure, `NoteGeometry.swift`): `NSAttributedString.boundingRect` at the card font and inner width + padding, clamped to a minimum of 80.
- **Color:** `.contextMenu` on notes with a "Color" submenu of `FolderColor.allCases`.
- Empty notes are kept (not auto-deleted).

## Phase 2 — Containers

- **Create:** Add ▸ Row/Column Container inserts an empty container at `visibleCenter()`: header "Untitled" placeholder + "Drop photos here" hint, minimum size 240×160.
- **`ContainerView`:** rounded background (`colorName` at low opacity + stroke), header band with tinted SF Symbol + title. Double-click on header → inline `TextField` rename (same `clickCount` path, `editingItemID`). Context menu: **Appearance…** (popover) and **Switch to Row / Column** (flip `axis`, relayout).
- **Appearance picker reuse:** refactor `FolderAppearancePicker` to take `iconName: Binding<String>`, `colorName: Binding<String>` (+ saving via modelContext as today); the sidebar passes the folder's bindings, containers pass theirs.
- **Layout (pure, `ContainerLayout.swift`):**
  - `stackLayout(axis:topLeft:sizes:) -> (centers: [CGPoint], containerSize: CGSize)` — header (32) + padding (12) + children edge-to-edge with 12 gap, centered on the cross axis; empty → minimum size.
  - `stackInsertionIndex(axis:point:existingCenters:) -> Int` — count of existing children whose center is before `point` along the axis.
  - `relayout(_ container: BoardItem)` — sorts `stackedItems` by `stackOrder`, renumbers 0…n-1, writes child centers and container `width/height`; **top-left stays fixed** (grows down for column, right for row). Called after insert, remove, reorder, child delete, align, axis switch. Ensures children `zIndex` > container `zIndex`.
- **Drag:**
  - Live move set: `expandingContainers(_ ids: Set<UUID>, children: [UUID: [UUID]]) -> Set<UUID>` (pure, next to `itemsToMove` in `BoardSelectionGeometry.swift`) so dragging a container moves its photos. `commitGroupMove` already preserves relative z-order.
  - Live drop target: while the moving set contains images and no containers, `dropTargetContainerID` (plain `@State`) = topmost container (not in the moving set) containing the dragged item's live center. Highlighted with an accent stroke.
  - On end with a target: the moving `.image` items get `container = target`, inserted at `stackInsertionIndex` (several → in their on-screen axis order); relayout the target and every previous container.
  - On end without a target: moving images whose container is *not* also moving leave the stack (`container = nil`), keep their dropped position; relayout old containers.
  - All of this runs in `.onEnded` (invariant 2).
- **Finder drop:** `.onDrop` hit-tests the topmost container at the drop point; `ImageImportService.importDroppedItems(…, container:)` / `insertImage(…, container:)` gain an optional `container: BoardItem? = nil` that appends at the end of the stack and relays out.
- **Interactions:** alignment skips items with a `container`, and relayouts any aligned container; deleting a container nullifies children (they stay put); Download includes stacked photos.

## Phase 3 — Connectors

- **Toolbar:** with exactly 2 items selected → **Connect** (`link`); if `connectorExists(between:and:in:)` (pure, either direction) → **Unlink** instead.
- **`ConnectorLayerView`** inside the scaled ZStack, above the background, below items. Per connector, endpoints from pure `connectorEndpoints(from: CGRect, to: CGRect) -> (CGPoint, CGPoint)?` (`ConnectorGeometry.swift`): clip the center-to-center segment to each rect's boundary; `nil` if the rects overlap (no line — e.g. photo connected to its own container). Rects include `liveTranslation` for moving items so lines follow drags without model writes.
- **Style:** 2pt; gray on light board, light gray on dark. Selected: accent color, 3pt.
- **Selection:** hit area = path stroked at 12pt (`contentShape`). Click sets `selectedConnectorID` (ephemeral `@State` in `BoardView`, passed down as a binding), mutually exclusive with `selectedItemIDs`. When set, toolbar shows **Unlink**; Delete key and the line's context menu "Unlink" also remove it.
- Deleting either endpoint removes the connector by cascade.

## Files

New: `moody/Models/BoardConnector.swift`, `moody/Views/Annotations/{NoteCardView,ContainerView,ConnectorLayerView,NoteGeometry,ContainerLayout,ConnectorGeometry}.swift`, matching tests in `moodyTests/`.
Modified: `BoardItem.swift`, `moodyApp.swift`, `BoardView.swift`, `BoardCanvasView.swift` (controller `visibleCenter`, connectors passthrough), `BoardDocumentContentView.swift`, `BoardItemView.swift`, `BoardSelectionGeometry.swift`, `ImageImportService.swift`, `ImageCache.swift` (evict), `FolderAppearancePicker.swift` + its sidebar call site, test container setups, `CLAUDE.md` architecture section.

Reused: `commitGroupMove`, `nextZIndex`, `itemsIntersecting`, `boardContentBounds`, `logicalPoint(from:)` (outer views only; inner gestures add `extent.origin`), `FolderColor`/`FolderIcon`, `FileStorageService.deleteFile`, `BoardCanvasController` bridge pattern.

## Invariants preserved
1. Zoom stays SwiftUI `.scaleEffect`; connector layer and new views live inside the scaled ZStack.
2. No `@Model` writes mid-gesture: stack membership, order, relayout, note text/height are committed only in `.onEnded` / editor commit / toolbar action. Drop-target highlight, editing id, selected connector are plain `@State`.

## Testing & verification
- **Unit (Swift Testing):** `BoardItemKind` fallback; `noteHeight` min + growth; `stackLayout` row/column/empty and top-left anchoring; `stackInsertionIndex` start/middle/end; `expandingContainers`; `connectorEndpoints` horizontal/diagonal/overlap→nil; `connectorExists` both directions.
- **SwiftData (in-memory):** item delete cascades connectors; container delete nullifies children; project delete removes connectors; `insertImage(container:)` appends + relayouts; a store with pre-existing rows reads `kind == .image`.
- **Commands:** `swiftformat --lint .`, `swiftlint lint --strict`, `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS'` green after each phase.
- **Manual QA (zoom 1 and ≠1):** add/edit/color/delete note; double-click edits without breaking single-click select; create container, drag photos in/out/reorder, multi-photo drop order, Finder drop into container, move container with children; connect/unlink, line follows live drag, click-select line, Delete key; delete photo shows confirmation and removes the file; existing board opens unchanged.

## Out of scope
Note resize handle, rich text, notes inside containers, arrowheads/labels on lines, drag-handle connector creation, undo.
