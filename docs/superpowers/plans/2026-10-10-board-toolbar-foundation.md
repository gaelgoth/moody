# Board Toolbar Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The board's window toolbar switches between a default set (Grid, Theme, Download All) and a selection set (Download Selected). Grid and theme are saved per board, and download copies the stored image files into a folder the user picks.

**Architecture:**
- The selection moves from `BoardDocumentContentView` up to `BoardView` and is passed down as a binding, so the toolbar can read it.
- `Project` gains two `Bool` settings, which are drawn by a new background `Canvas` layer inside the scaled content.
- Export is a pure file-copy method on `FileStorageService`, driven from `BoardView` through an `NSOpenPanel`.

**Tech Stack:** Swift, SwiftUI, AppKit (`NSOpenPanel`, `NSScrollView`), SwiftData, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-10-board-toolbar-foundation-design.md`

## Global Constraints

- macOS 27, Xcode 27. `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. `FileStorageService` is `nonisolated`, and free helper functions follow the existing convention (plain `func`, as in `CanvasExtent.swift`).
- Lint must pass: `swiftformat --lint .` and `swiftlint lint --strict`. The rules are 4-space indent, 140-col lines, mandatory trailing commas in multi-line collections, and `@testable import` last.
- New files in `moody/` or `moodyTests/` are picked up automatically. Don't edit `project.pbxproj` except for the one sandbox setting in Task 1.
- **No `@Model` writes mid-gesture.** This change mustn't add any writes inside `.onChanged`.
- Grid spacing is 40 board points. Line colour is black at 8 % opacity on white, or white at 12 % on black. Line width is 1.
- Toolbar copy:
  - "Zoom to Fit", "Grid", "Dark Background" / "Light Background", "Download All", "Download Selected".
  - Help text "Download Image" for 1 selected, "Download N Images" for more.
  - Panel prompt "Download". Failure alert "N images couldn't be downloaded." (for 1: "1 image couldn't be downloaded.").
- **Don't commit.** The user commits their own work. There are no `git add`/`git commit` steps.

## Review Focus

1. **Re-downloading into the same folder** must overwrite silently, not fail. *(Task 1 test)*
2. **A missing source file** must not delete an existing copy in the destination, and must not stop the other files. *(Task 1 test)*
3. **Panning into negative board coordinates** must keep grid lines pinned to board multiples of 40, including when the origin is exactly a multiple. *(Task 2 tests)*
4. **A selection that includes a deleted item** must not show "Download Selected" for 0 images. The toolbar uses the resolved `selectedItems`, not the raw id set. *(Task 4, manual step)*
5. **Toggling the theme on an open board** must also recolour the elastic overscroll area. BoardView's body reads `usesDarkBackground`, so `updateNSView` re-runs. *(Task 3, manual step)*

---

### Task 1: File export on FileStorageService (+ sandbox write access)

**Files:**
- Modify: `moody/Storage/FileStorageService.swift`
- Modify: `moody.xcodeproj/project.pbxproj` (two `ENABLE_USER_SELECTED_FILES` lines)
- Test: `moodyTests/FileStorageServiceTests.swift`

**Interfaces:**
- Produces: `func exportFiles(fileNames: [String], projectID: UUID, to folder: URL) -> [String]` on `FileStorageService`. It returns the file names that were **not** copied.

- [ ] **Step 1: Write the failing tests.** Append inside `struct FileStorageServiceTests`:

```swift
    @Test func exportingCopiesOnlyTheRequestedFiles() throws {
        let storage = try FileStorageService(rootDirectory: makeTempRoot())
        let destination = try makeTempRoot()
        let projectID = UUID()
        try storage.write(data: Data("one".utf8), fileName: "one.png", projectID: projectID)
        try storage.write(data: Data("two".utf8), fileName: "two.png", projectID: projectID)

        let failed = storage.exportFiles(fileNames: ["one.png"], projectID: projectID, to: destination)

        #expect(failed.isEmpty)
        #expect(try Data(contentsOf: destination.appendingPathComponent("one.png")) == Data("one".utf8))
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("two.png").path))
    }

    @Test func exportingReplacesAnExistingFileOfTheSameName() throws {
        let storage = try FileStorageService(rootDirectory: makeTempRoot())
        let destination = try makeTempRoot()
        let projectID = UUID()
        try storage.write(data: Data("new".utf8), fileName: "one.png", projectID: projectID)
        try Data("old".utf8).write(to: destination.appendingPathComponent("one.png"))

        let failed = storage.exportFiles(fileNames: ["one.png"], projectID: projectID, to: destination)

        #expect(failed.isEmpty)
        #expect(try Data(contentsOf: destination.appendingPathComponent("one.png")) == Data("new".utf8))
    }

    @Test func exportingReportsAMissingFileWithoutTouchingItsExistingCopyAndStillCopiesTheRest() throws {
        let storage = try FileStorageService(rootDirectory: makeTempRoot())
        let destination = try makeTempRoot()
        let projectID = UUID()
        try storage.write(data: Data("two".utf8), fileName: "two.png", projectID: projectID)
        try Data("earlier".utf8).write(to: destination.appendingPathComponent("missing.png"))

        let failed = storage.exportFiles(fileNames: ["missing.png", "two.png"], projectID: projectID, to: destination)

        #expect(failed == ["missing.png"])
        #expect(try Data(contentsOf: destination.appendingPathComponent("missing.png")) == Data("earlier".utf8))
        #expect(try Data(contentsOf: destination.appendingPathComponent("two.png")) == Data("two".utf8))
    }
```

- [ ] **Step 2: Run the tests and confirm they fail.**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/FileStorageServiceTests`
Expected: build failure, "value of type 'FileStorageService' has no member 'exportFiles'".

- [ ] **Step 3: Implement.** Add after `deleteProjectDirectory` in `FileStorageService`:

```swift
    /// Copies each stored file into `folder`, replacing any file of the same
    /// name. Returns the names that could not be copied; one failure doesn't
    /// stop the rest.
    func exportFiles(fileNames: [String], projectID: UUID, to folder: URL) -> [String] {
        let fileManager = FileManager.default
        var failed: [String] = []
        for fileName in fileNames {
            let source = fileURL(fileName: fileName, projectID: projectID)
            let destination = folder.appendingPathComponent(fileName, isDirectory: false)
            // Check the source first so a missing file never deletes the user's earlier copy.
            guard fileManager.fileExists(atPath: source.path) else {
                failed.append(fileName)
                continue
            }
            do {
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: source, to: destination)
            } catch {
                failed.append(fileName)
            }
        }
        return failed
    }
```

- [ ] **Step 4: Grant sandbox write access to user-selected folders.**

Run: `sed -i '' 's/ENABLE_USER_SELECTED_FILES = readonly;/ENABLE_USER_SELECTED_FILES = readwrite;/' moody.xcodeproj/project.pbxproj && grep -n ENABLE_USER_SELECTED_FILES moody.xcodeproj/project.pbxproj`
Expected: exactly two lines, both `= readwrite;`.

- [ ] **Step 5: Run the tests and confirm they pass.**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/FileStorageServiceTests`
Expected: all 6 tests pass.

---

### Task 2: Grid line geometry helper

**Files:**
- Create: `moody/Views/BoardGrid.swift`
- Test: `moodyTests/BoardGridTests.swift`

**Interfaces:**
- Produces:
  - `let boardGridSpacing: CGFloat` (= 40)
  - `func gridLineOffsets(origin: CGFloat, length: CGFloat, spacing: CGFloat) -> [CGFloat]`, which returns the local offsets within `origin ..< origin + length` of every board-space multiple of `spacing`.

- [ ] **Step 1: Write the failing tests.** Create `moodyTests/BoardGridTests.swift`:

```swift
//
//  BoardGridTests.swift
//  moodyTests
//

import CoreGraphics
import Testing
@testable import moody

struct BoardGridTests {
    @Test func originAtZeroStartsAtZero() {
        #expect(gridLineOffsets(origin: 0, length: 100, spacing: 40) == [0, 40, 80])
    }

    @Test func negativeNonMultipleOriginStartsAtTheNextBoardMultiple() {
        // Board lines at -40, 0, 40 → local 10, 50, 90.
        #expect(gridLineOffsets(origin: -50, length: 100, spacing: 40) == [10, 50, 90])
    }

    @Test func originExactlyOnAMultipleStartsAtZero() {
        #expect(gridLineOffsets(origin: -80, length: 100, spacing: 40) == [0, 40, 80])
    }

    @Test func lengthShorterThanFirstOffsetIsEmpty() {
        #expect(gridLineOffsets(origin: 30, length: 5, spacing: 40).isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail.**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/BoardGridTests`
Expected: build failure, "cannot find 'gridLineOffsets' in scope".

- [ ] **Step 3: Implement.** Create `moody/Views/BoardGrid.swift`:

```swift
//
//  BoardGrid.swift
//  moody
//
//  Background grid geometry. Lines sit on board-space multiples of the
//  spacing, so they stay pinned to the board when extent.origin shifts.
//

import CoreGraphics

let boardGridSpacing: CGFloat = 40

/// Local offsets, within an extent spanning `origin ..< origin + length`, of
/// every board-space multiple of `spacing`.
func gridLineOffsets(origin: CGFloat, length: CGFloat, spacing: CGFloat) -> [CGFloat] {
    let first = (origin / spacing).rounded(.up) * spacing - origin
    return Array(stride(from: first, to: length, by: spacing))
}
```

- [ ] **Step 4: Run the tests and confirm they pass.**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/BoardGridTests`
Expected: 4 tests pass.

---

### Task 3: Board settings + background/grid rendering

**Files:**
- Modify: `moody/Models/Project.swift`
- Modify: `moody/Views/BoardGrid.swift` (add `BoardBackgroundView`)
- Modify: `moody/Views/BoardDocumentContentView.swift:92-94` (the `Color.clear` layer)
- Modify: `moody/Views/BoardCanvasView.swift:65-73` (`updateNSView`)

**Interfaces:**
- Consumes: `gridLineOffsets`, `boardGridSpacing` (Task 2).
- Produces:
  - `Project.showsGrid: Bool` and `Project.usesDarkBackground: Bool`, both defaulting to `false`.
  - `struct BoardBackgroundView: View` with `extent: CGRect`, `showsGrid: Bool`, `isDark: Bool`.

- [ ] **Step 1: Add the settings to `Project`.** Insert after `var folder: Folder?`:

```swift
    /// Board look, toggled from BoardView's toolbar. Defaults keep
    /// SwiftData's lightweight migration working for existing stores.
    var showsGrid: Bool = false
    var usesDarkBackground: Bool = false
```

- [ ] **Step 2: Add the background view.** Append to `moody/Views/BoardGrid.swift`, and change the import to `import SwiftUI` (it re-exports CoreGraphics):

```swift
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
```

- [ ] **Step 3: Use it as the marquee layer.** In `BoardDocumentContentView.body`, replace:

```swift
            Color.clear
                .contentShape(Rectangle())
                .gesture(marqueeGesture)
```

with:

```swift
            BoardBackgroundView(extent: extent, showsGrid: project.showsGrid, isDark: project.usesDarkBackground)
                .contentShape(Rectangle())
                .gesture(marqueeGesture)
```

- [ ] **Step 4: Match the scroll view's overscroll colour.** In `BoardCanvasView`, replace `updateNSView`:

```swift
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
```

Also add `scrollView.backgroundColor = project.usesDarkBackground ? .black : .white` in `makeNSView`, right after `scrollView.hasVerticalScroller = true`.

- [ ] **Step 5: Build and run the full suite.**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS'`
Expected: all tests pass. The new properties have defaults, so existing tests and the in-memory containers need no changes.

The toggles arrive in Task 4. Manual check of this task: temporarily flip the `Project` defaults to `true`, run the app, and confirm a black board with a faint grid. **Revert the defaults to `false` afterwards.**

---

### Task 4: Lift selection, dynamic toolbar, download UI, docs

**Files:**
- Modify: `moody/Views/BoardDocumentContentView.swift:14-24` (header comment) and `:55-57` (`selectedItemIDs`)
- Modify: `moody/Views/BoardCanvasView.swift:40-46` (properties) and `:108-116` (`makeContent`)
- Modify: `moody/Views/BoardView.swift` (whole body)
- Modify: `CLAUDE.md` (Canvas view stack paragraph)

**Interfaces:**
- Consumes:
  - `FileStorageService.exportFiles(fileNames:projectID:to:) -> [String]` (Task 1).
  - `Project.showsGrid` and `Project.usesDarkBackground` (Task 3).
- Produces:
  - `BoardCanvasView.selectedItemIDs: Binding<Set<UUID>>` and `BoardDocumentContentView.selectedItemIDs: Binding<Set<UUID>>`.
  - `BoardView` owns `@State selectedItemIDs`. Sub-projects 2 and 4 will add selection actions next to Download Selected.

- [ ] **Step 1: Turn the content's selection into a binding.** In `BoardDocumentContentView`, replace:

```swift
    /// Ids of the currently multi-selected items. Ephemeral UI state, never
    /// persisted — resets whenever the board is reopened.
    @State private var selectedItemIDs: Set<UUID> = []
```

with (and move it up next to the other bindings, after `zoomAnchor`):

```swift
    /// Ids of the currently selected items. Owned by BoardView (its toolbar
    /// acts on the selection); ephemeral, never persisted.
    @Binding var selectedItemIDs: Set<UUID>
```

In the file header, change "Selection and drag state both live here" to "Drag state lives here, and selection is edited here (BoardView owns it)". No other line in this file changes, because the handlers already assign `selectedItemIDs`.

- [ ] **Step 2: Thread the binding through `BoardCanvasView`.** Add after `@Binding var zoomAnchor: CGPoint?`:

```swift
    /// Owned by BoardView so its toolbar can act on the selection.
    @Binding var selectedItemIDs: Set<UUID>
```

and in `Coordinator.makeContent()` add the argument after `zoomAnchor:`:

```swift
                zoomAnchor: parent.$zoomAnchor,
                selectedItemIDs: parent.$selectedItemIDs
```

- [ ] **Step 3: Rewrite `BoardView`.** Replace the whole file content after the header with:

```swift
import AppKit
import SwiftData
import SwiftUI

struct BoardView: View {
    @Bindable var project: Project
    @Query private var items: [BoardItem]
    @Environment(\.modelContext) private var modelContext
    @State private var zoomScale: CGFloat = 1
    /// Board-space point under the cursor, kept up to date by hover so
    /// pinch-zoom is anchored at the cursor. nil until the mouse first moves
    /// over the board (zoom then anchors at the viewport center).
    @State private var zoomAnchor: CGPoint?
    @State private var canvasController = BoardCanvasController()
    /// Lives here (not in the canvas content) so the toolbar can switch to
    /// selection actions. Ephemeral; resets per board.
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var failedDownloadCount = 0
    @State private var isShowingDownloadFailure = false

    init(project: Project) {
        _project = Bindable(project)
        let projectID = project.id
        _items = Query(
            filter: #Predicate<BoardItem> { $0.project?.id == projectID },
            sort: \BoardItem.zIndex
        )
    }

    /// Resolved against `items` so ids of deleted items are ignored.
    private var selectedItems: [BoardItem] {
        items.filter { selectedItemIDs.contains($0.id) }
    }

    var body: some View {
        BoardCanvasView(
            project: project,
            items: items,
            zoomScale: $zoomScale,
            zoomAnchor: $zoomAnchor,
            selectedItemIDs: $selectedItemIDs,
            controller: canvasController
        )
        .overlay(alignment: .bottomTrailing) {
            Text(zoomScale, format: .percent.precision(.fractionLength(0)))
                .font(.caption)
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
                .padding(12)
                .allowsHitTesting(false)
        }
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
            if selectedItems.isEmpty {
                ToolbarItemGroup(placement: .primaryAction) {
                    Toggle("Grid", systemImage: "grid", isOn: $project.showsGrid)
                        .help("Grid")
                    Button(
                        project.usesDarkBackground ? "Light Background" : "Dark Background",
                        systemImage: project.usesDarkBackground ? "sun.max" : "moon"
                    ) {
                        project.usesDarkBackground.toggle()
                    }
                    .help(project.usesDarkBackground ? "Light Background" : "Dark Background")
                    Button("Download All", systemImage: "square.and.arrow.down") {
                        download(items)
                    }
                    .help("Download All")
                    .disabled(items.isEmpty)
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button("Download Selected", systemImage: "square.and.arrow.down") {
                        download(selectedItems)
                    }
                    .help(selectedItems.count == 1 ? "Download Image" : "Download \(selectedItems.count) Images")
                }
            }
        }
        .onChange(of: project.showsGrid) { try? modelContext.save() }
        .onChange(of: project.usesDarkBackground) { try? modelContext.save() }
        .alert(
            failedDownloadCount == 1 ? "1 image couldn't be downloaded." : "\(failedDownloadCount) images couldn't be downloaded.",
            isPresented: $isShowingDownloadFailure
        ) {
            Button("OK") {}
        }
    }

    private func download(_ targets: [BoardItem]) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Download"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        // shortcut: copies synchronously on the main thread (APFS clones are near-instant); move off-main if large boards stall.
        let failed = FileStorageService().exportFiles(fileNames: targets.map(\.fileName), projectID: project.id, to: folder)
        failedDownloadCount = failed.count
        isShowingDownloadFailure = !failed.isEmpty
    }
}
```

- [ ] **Step 4: Update `CLAUDE.md`.** At the end of the "Canvas view stack" paragraph, after the Zoom to Fit sentence, append:

```markdown
`BoardView` owns the selection (`selectedItemIDs`, passed down as a binding through `BoardCanvasView.makeContent`) so its toolbar can switch between the default actions (Grid, Theme, Download All) and selection actions (Download Selected); resolve the id set against `items` before acting on it. Per-board look lives on `Project` (`showsGrid`, `usesDarkBackground`) and is drawn by `BoardBackgroundView` (`BoardGrid.swift`). Download copies stored files via `FileStorageService.exportFiles`, which needs the `ENABLE_USER_SELECTED_FILES = readwrite` sandbox setting.
```

- [ ] **Step 5: Lint, then run the full suite.**

Run: `swiftformat --lint . && swiftlint lint --strict && xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS'`
Expected: no lint violations and all tests pass, including the UI tests. `SidebarRenameUITests` still finds the window title.

- [ ] **Step 6: Manual QA in the running app.**

1. **Empty board:** the toolbar shows Zoom to Fit (disabled), Grid, Dark Background (moon), and Download All (disabled).
2. **Grid:** toggle it on. Lines appear. Pan far left and up into negative space, then zoom in and out: the lines stay fixed to the board and move with the images.
3. **Theme:** toggle it. The board turns black, and dragging past the edge with the trackpad (elastic overscroll) also shows black. *(Review Focus 5)*
4. **Persistence:** quit and relaunch. That board keeps its grid and theme, and another board keeps its own.
5. **Selection:** click an image. The toolbar swaps to Zoom to Fit and Download Selected, with help text "Download Image". Marquee-select 3 images and the help text reads "Download 3 Images". Click empty canvas and the default set returns.
6. **Download:** Download Selected → choose a new folder → exactly the selected files appear there. Repeat into the same folder: no error, and the files are overwritten. *(Review Focus 1)* Then Download All copies every file.
7. **Deleted item in the selection:** *(Review Focus 4)* The app has no item-delete UI yet, so instead switch boards and come back, and confirm the selection is empty and the default set shows. Check this again once item deletion exists.
