# Board toolbar foundation — design

Sub-project 1 of 4 of the "dynamic board toolbar" request. Later ones: 2 alignment, 3 notes, 4 connectors. Each gets its own spec and plan.

## Goal

The board's window toolbar changes its actions with the selection:

- **Nothing selected:** Zoom to Fit, Grid toggle, Theme toggle (white/black), Download All.
- **One or more images selected:** Zoom to Fit, Download Selected. Sub-project 2 adds alignment (disabled below 2 selected), and sub-project 4 adds Connect.

Notes (sub-project 3) will join the no-selection set. This spec adds no placeholder for it.

## Decisions

| Topic | Decision |
|---|---|
| Placement | Native window toolbar (`BoardView.toolbar`), not a canvas overlay. |
| Selection trigger | Any selection of ≥ 1 item switches to the selection set. |
| Download output | Copies the stored image files into a folder the user picks. SVGs come out as their rasterized PNGs (the only stored form). |
| Grid / theme persistence | Saved per board on `Project`. |

## Design

### 1. Selection ownership

`selectedItemIDs: Set<UUID>` moves from `@State` in `BoardDocumentContentView` to `@State` in `BoardView`. It reaches the content as a `@Binding` by the same route as `zoomScale`: `BoardView` → `BoardCanvasView.selectedItemIDs` → `Coordinator.makeContent()` → `BoardDocumentContentView`.

The marquee, click and drag handlers keep their logic and now write through the binding.

Selection is plain view state, not a `@Model` value, so changing it mid-gesture doesn't break the "no model writes mid-gesture" invariant. A selection change re-runs `updateNSView` → `refreshExtent`, which already happens on every hover update.

Ids of deleted items may linger in the set. Every consumer resolves the set against `items` (`items.filter { selectedItemIDs.contains($0.id) }`), so stale ids are ignored and the toolbar decides on the resolved set's count. Switching boards resets selection, because `BoardView` gets a fresh identity per project.

### 2. Board settings

`Project` gains:

```swift
var showsGrid: Bool = false
var usesDarkBackground: Bool = false
```

Both have defaults, so SwiftData's lightweight migration updates existing stores. The `Schema` doesn't change because no new model types are added.

### 3. Background and grid rendering

In `BoardDocumentContentView`, the `Color.clear` marquee layer becomes a background layer:

- It fills with `.white`, or `.black` when `usesDarkBackground` is on.
- When `showsGrid` is on, a SwiftUI `Canvas` draws 1 pt lines every 40 board points. The colour is black at 8 % opacity on white, or white at 12 % on black.
- It keeps `.contentShape(Rectangle())` and the marquee gesture.

The layer sits inside `.scaleEffect`, so the grid zooms with the content. Lines are pinned to board space: the line positions inside the extent come from the pure helper below, so they don't drift when `extent.origin` shifts.

```swift
/// Local x (or y) offsets, within an extent spanning `origin ..< origin + length`,
/// of every board-space multiple of `spacing`.
nonisolated func gridLineOffsets(origin: CGFloat, length: CGFloat, spacing: CGFloat) -> [CGFloat]
```

The helper lives in `moody/Views/BoardGrid.swift`. The first offset is `ceil(origin / spacing) * spacing - origin`, and offsets then step by `spacing` while `< length`.

`BoardCanvasView.updateNSView` also sets `scrollView.backgroundColor` to the matching `NSColor`, so elastic overscroll past the hosting view doesn't show the default window colour.

### 4. Toolbar

`BoardView.toolbar` has these items:

- **Zoom to Fit** stays the same as today and always shows.
- **No selection:**
  - Grid: `Toggle("Grid", systemImage: "grid", isOn: $project.showsGrid)`. Changes are saved with `modelContext.save()`.
  - Theme: a button showing `moon` on a white board and `sun.max` on a black one. It toggles `usesDarkBackground` and saves. Help text: "Dark Background" / "Light Background".
  - Download All: `square.and.arrow.down`, disabled when `items.isEmpty`.
- **Selection ≥ 1:**
  - Download Selected: `square.and.arrow.down`, help text "Download N Images".

The two sets are written as an `if`/`else` inside `.toolbar`.

### 5. Download

`FileStorageService` gains:

```swift
/// Copies each stored file into `folder`, replacing any file of the same name.
/// Returns the names that could not be copied; one failure doesn't stop the rest.
func exportFiles(fileNames: [String], projectID: UUID, to folder: URL) -> [String]
```

For each name it removes `folder/<fileName>` if present, then copies `fileURL(fileName:projectID:)` there. Stored names are `<UUID>.<ext>`, so a name clash only happens when re-exporting the same image, and replacing it is correct.

`BoardView` runs the UI:

1. It presents an `NSOpenPanel` (`canChooseDirectories = true`, `canChooseFiles = false`, `canCreateDirectories = true`, `prompt = "Download"`).
2. When the user picks a folder, it calls `exportFiles` with the target items' `fileName`s.
3. If any copy fails, it shows an alert: "N images couldn't be downloaded."

**Sandbox:** user-selected files are currently `ENABLE_USER_SELECTED_FILES = readonly` (Debug and Release). This must change to `readwrite`, or writing into the chosen folder fails.

### 6. Testing

Swift Testing, in `moodyTests/`:

- `FileStorageServiceTests`, using the existing temp `rootDirectory` and a temp destination folder:
  - Export copies exactly the requested files, byte for byte.
  - Export replaces an existing file of the same name.
  - A missing source file is reported in the result, and the other files are still copied.
- `BoardGridTests`:
  - Origin 0 gives offsets 0, 40, 80, …
  - A negative, non-multiple origin (e.g. −50) gives a first offset of 10.
  - `length` shorter than the first offset gives an empty result.

Toolbar switching, the grid look and the theme are checked by hand in the running app.

### 7. Docs

Update `CLAUDE.md` (Canvas view stack):

- `BoardView` owns the selection and passes it down as a binding.
- The toolbar switches its actions on the resolved selection.
- `Project` carries `showsGrid` / `usesDarkBackground`.

## Out of scope

- Alignment, notes and connectors: sub-projects 2–4.
- Exporting a rendered board image or a zip.
- Grid spacing or colour options.
- Any background colour other than white and black.
