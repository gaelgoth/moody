# Board Annotations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add sticky Notes, row/column photo Containers, and Connector lines to the board, plus the Delete action they need.

**Architecture:** Notes and containers are `BoardItem`s with a `kind` discriminator, so the existing center+size machinery (drag, marquee, z-order, extent, alignment) keeps working; connectors are a separate `BoardConnector` model cascade-deleted with either endpoint. Stack layout, insertion index, hit-testing and line geometry are pure free functions; model writes (`relayout`, `insertIntoStack`, `commitStackDrop`, `deleteBoardItems`) are free functions like `commitGroupMove`, called only from `.onEnded`, toolbar actions, editor end or import.

**Tech Stack:** Swift, SwiftUI + AppKit, SwiftData, Swift Testing. macOS 27 / Xcode 27.

**Spec:** `docs/superpowers/specs/2026-10-10-board-annotations-design.md`

## Global Constraints

- Every new `@Model` field has a default value (lightweight migration only, no `VersionedSchema`).
- Every new `@Model` type is added to the `Schema` in `moody/moodyApp.swift` and to every test container (`grep -rn "BoardItem.self" moody moodyTests`).
- Invariant 1: zoom stays SwiftUI `.scaleEffect`; all new board views live inside the scaled ZStack. Gestures inside the ZStack add `extent.origin`; only outer views (hover, drop) use `logicalPoint(from:)`.
- Invariant 2: no `@Model` writes mid-gesture. Stack membership/order/relayout are written only in `.onEnded`; drop-target highlight, editing id and selected connector are plain `@State`.
- Lint: `swiftformat --lint .` and `swiftlint lint --strict` must pass (4-space indent, 140 cols, mandatory trailing commas, identifiers ≥ 2 chars except `id x y dx dy a b c`, tuples ≤ 3 members).
- `MainActor` is the default isolation; pure helpers that must run off-main get `nonisolated` (none here need it).
- No `git add` / `git commit` steps: the user commits their own work.
- Test command template: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/<Suite>`.

## Review Focus

1. Pressing ⌫ while typing in a note, a container title, or the sidebar rename field must edit the text, not delete board items. Pinned by the manual QA steps in Task 2 and Task 5.
2. A board saved before this change opens with every photo intact and still treated as a photo. Pinned by `itemsDefaultToTheImageKind` and `unknownKindFallsBackToImage` in Task 1.
3. Deleting a photo whose file is already gone from disk still removes it from the board. Pinned by `deletingAPhotoWithAMissingFileStillRemovesIt` in Task 2.
4. Clicking (not dragging) a stacked photo, or dropping it back in its own slot, must not reorder the stack. Pinned by `reinsertingAtItsOwnIndexKeepsTheOrder` in Task 7, plus the `translation != .zero` guard in Task 9.
5. A photo connected to its own container (the boxes overlap) draws no line and doesn't crash; deleting that container keeps the photo and drops the connector. Pinned by `overlappingBoxesHaveNoLine` in Task 11 and `deletingAContainerLeavesItsPhotosLooseAndDropsItsConnectors` in Task 7.

---

# Phase 0 — Foundation: kind + Delete

### Task 1: `BoardItem` kind, stack fields, and `BoardConnector` model

**Files:**
- Modify: `moody/Models/BoardItem.swift`
- Create: `moody/Models/BoardItemKind.swift`
- Create: `moody/Models/BoardConnector.swift`
- Modify: `moody/moodyApp.swift:14-18`
- Modify (schema lists): `moodyTests/BoardGroupMoveTests.swift:14`, `moodyTests/FolderCascadeDeleteTests.swift:13`, `moodyTests/ProjectCascadeDeleteTests.swift:12`, `moodyTests/SidebarTreeTests.swift:13`, `moodyTests/ImageImportServiceTests.swift:19`, `moody/Views/Sidebar/FolderAppearancePicker.swift:83` (preview)
- Test: `moodyTests/BoardItemModelTests.swift`

**Interfaces:**
- Produces: `enum BoardItemKind: String { image, note, container }`, `enum StackAxis: String { row, column }`; on `BoardItem`: `kindRaw`, `kind`, `text`, `colorName`, `title`, `iconName`, `axisRaw`, `axis` (get/set), `container: BoardItem?`, `stackedItems: [BoardItem]`, `stackOrder: Int`, `outgoingConnectors`, `incomingConnectors`, `resolvedColor: FolderColor`, `resolvedIconName: String`, `center: CGPoint`, `size: CGSize`; init gains `kind: BoardItemKind = .image`. `@Model final class BoardConnector { id, from: BoardItem?, to: BoardItem?, createdAt }`, `init(id:from:to:createdAt:)`.

- [ ] **Step 1: Write the failing test**

Create `moodyTests/BoardItemModelTests.swift`:

```swift
//
//  BoardItemModelTests.swift
//  moodyTests
//

import Foundation
import SwiftData
import Testing
@testable import moody

struct BoardItemModelTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Project.self, BoardItem.self, BoardConnector.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeItem(in project: Project, context: ModelContext, kind: BoardItemKind = .image) -> BoardItem {
        let item = BoardItem(
            fileName: kind == .image ? "\(UUID().uuidString).png" : "",
            positionX: 0,
            positionY: 0,
            width: 100,
            height: 100,
            pixelWidth: 100,
            pixelHeight: 100,
            zIndex: 1,
            kind: kind,
            project: project
        )
        context.insert(item)
        return item
    }

    @Test func itemsDefaultToTheImageKind() throws {
        let context = try makeContext()
        let project = Project(name: "Board")
        context.insert(project)
        let item = BoardItem(
            fileName: "a.png", positionX: 0, positionY: 0, width: 10, height: 10,
            pixelWidth: 10, pixelHeight: 10, zIndex: 1, project: project
        )
        context.insert(item)
        #expect(item.kind == .image)
        #expect(item.kindRaw == "image")
    }

    @Test func unknownKindFallsBackToImage() throws {
        let context = try makeContext()
        let project = Project(name: "Board")
        context.insert(project)
        let item = makeItem(in: project, context: context, kind: .note)
        item.kindRaw = "sticker"
        #expect(item.kind == .image)
    }

    @Test func unknownColorAndIconFallBackToDefaults() throws {
        let context = try makeContext()
        let project = Project(name: "Board")
        context.insert(project)
        let note = makeItem(in: project, context: context, kind: .note)
        note.colorName = "plaid"
        note.iconName = "not.a.symbol"
        #expect(note.resolvedColor == .yellow)
        #expect(note.resolvedIconName == "photo")
    }

    @Test func deletingAnItemDeletesItsConnectors() throws {
        let context = try makeContext()
        let project = Project(name: "Board")
        context.insert(project)
        let a = makeItem(in: project, context: context)
        let b = makeItem(in: project, context: context, kind: .note)
        context.insert(BoardConnector(from: a, to: b))
        try context.save()

        context.delete(b)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<BoardConnector>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<BoardItem>()).count == 1)
    }

    @Test func deletingAProjectDeletesItsConnectors() throws {
        let context = try makeContext()
        let project = Project(name: "Board")
        context.insert(project)
        let a = makeItem(in: project, context: context)
        let b = makeItem(in: project, context: context)
        context.insert(BoardConnector(from: a, to: b))
        try context.save()

        context.delete(project)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<BoardConnector>()).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/BoardItemModelTests`
Expected: build FAILS with "cannot find 'BoardConnector' in scope" / "extra argument 'kind' in call".

- [ ] **Step 3: Create `moody/Models/BoardConnector.swift`**

```swift
//
//  BoardConnector.swift
//  moody
//
//  A straight line linking two board items (photo, note or container).
//  Deleting either end deletes the connector (cascade rules on BoardItem).
//

import Foundation
import SwiftData

@Model
final class BoardConnector {
    var id: UUID
    var from: BoardItem?
    var to: BoardItem?
    var createdAt: Date

    init(id: UUID = UUID(), from: BoardItem?, to: BoardItem?, createdAt: Date = .now) {
        self.id = id
        self.from = from
        self.to = to
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 4: Add the fields to `moody/Models/BoardItem.swift`**

Insert after `var project: Project?`:

```swift

    /// `BoardItemKind` raw value; read through `kind`. Every field below has a
    /// default so lightweight migration keeps existing boards (all photos) working.
    var kindRaw: String = "image"
    /// Note body.
    var text: String = ""
    /// `FolderColor` raw value tinting a note or container; read through `resolvedColor`.
    var colorName: String = "yellow"
    /// Container header title.
    var title: String = ""
    /// Container header SF Symbol; read through `resolvedIconName`.
    var iconName: String = "photo"
    /// `StackAxis` raw value; read through `axis`.
    var axisRaw: String = "column"
    /// The container this photo is stacked in; nil = loose on the board.
    var container: BoardItem?
    /// Position within `container`'s stack, 0 first.
    var stackOrder: Int = 0

    /// Deleting a container leaves its photos on the board, loose.
    @Relationship(deleteRule: .nullify, inverse: \BoardItem.container)
    var stackedItems: [BoardItem] = []

    /// Deleting either end of a connector deletes the connector.
    @Relationship(deleteRule: .cascade, inverse: \BoardConnector.from)
    var outgoingConnectors: [BoardConnector] = []
    @Relationship(deleteRule: .cascade, inverse: \BoardConnector.to)
    var incomingConnectors: [BoardConnector] = []
```

Change the init: add a `kind: BoardItemKind = .image,` parameter between `zIndex: Int,` and `createdAt: Date = .now,`, and add `kindRaw = kind.rawValue` after `self.zIndex = zIndex`. Also update the `fileName` doc comment to: `/// Bare leaf filename of the stored image (never an absolute path); "" for notes and containers.`

- [ ] **Step 5: Create `moody/Models/BoardItemKind.swift`**

```swift
//
//  BoardItemKind.swift
//  moody
//
//  What a BoardItem is. Stored as plain strings so an unknown value (e.g.
//  from a newer build) falls back instead of failing to load the board.
//

import CoreGraphics
import Foundation

enum BoardItemKind: String {
    case image
    case note
    case container
}

enum StackAxis: String {
    case row
    case column
}

extension BoardItem {
    var kind: BoardItemKind {
        BoardItemKind(rawValue: kindRaw) ?? .image
    }

    var axis: StackAxis {
        get { StackAxis(rawValue: axisRaw) ?? .column }
        set { axisRaw = newValue.rawValue }
    }

    var resolvedColor: FolderColor {
        FolderColor(rawValue: colorName) ?? (kind == .container ? FolderColor.defaultColor : .yellow)
    }

    var resolvedIconName: String {
        FolderIcon.all.contains(iconName) ? iconName : "photo"
    }

    var center: CGPoint {
        CGPoint(x: positionX, y: positionY)
    }

    var size: CGSize {
        CGSize(width: width, height: height)
    }
}
```

- [ ] **Step 6: Register `BoardConnector` everywhere `BoardItem.self` is listed**

Run `grep -rn "BoardItem.self" moody moodyTests` and append `BoardConnector.self` after each `BoardItem.self`: `moody/moodyApp.swift` (add a `BoardConnector.self,` line after `BoardItem.self,`), the four test `Schema([...])` lists, `ImageImportServiceTests` (`for: Folder.self, Project.self, BoardItem.self, BoardConnector.self,`), and the `FolderAppearancePicker` preview `.modelContainer(for: [...])`.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS'`
Expected: all tests PASS (new suite plus every existing suite).

- [ ] **Step 8: Lint**

Run: `swiftformat . && swiftlint lint --strict`
Expected: no violations.

---

### Task 2: Delete selected items (toolbar + ⌫) and image-only paths

**Files:**
- Create: `moody/Views/BoardDeletion.swift`
- Modify: `moody/Storage/ImageCache.swift`
- Modify: `moody/Views/BoardCanvasView.swift` (property `onDeleteKey`, key monitor in Coordinator, `dismantleNSView`)
- Modify: `moody/Views/BoardView.swift` (Delete button, confirmation alert, download filters, canvas call site)
- Modify: `moody/Views/BoardItemView.swift:45-47` (`.task` guard)
- Test: `moodyTests/BoardDeletionTests.swift`

**Interfaces:**
- Consumes: `BoardItem.kind` (Task 1).
- Produces: `func deleteBoardItems(_ items: [BoardItem], context: ModelContext, storage: FileStorageService = FileStorageService(), cache: ImageCache = .shared)`; `ImageCache.evict(fileName: String)`; `BoardCanvasView.onDeleteKey: () -> Bool` (declared after `controller`); `BoardView.handleDeleteKey() -> Bool`.

- [ ] **Step 1: Write the failing test**

Create `moodyTests/BoardDeletionTests.swift`:

```swift
//
//  BoardDeletionTests.swift
//  moodyTests
//

import Foundation
import SwiftData
import Testing
@testable import moody

@MainActor
struct BoardDeletionTests {
    private func makeStorage() -> FileStorageService {
        FileStorageService(rootDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("moody-tests-\(UUID().uuidString)", isDirectory: true))
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Project.self, BoardItem.self, BoardConnector.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    private func makeItem(_ fileName: String, kind: BoardItemKind, project: Project, context: ModelContext) -> BoardItem {
        let item = BoardItem(
            fileName: fileName, positionX: 0, positionY: 0, width: 100, height: 100,
            pixelWidth: 100, pixelHeight: 100, zIndex: 1, kind: kind, project: project
        )
        context.insert(item)
        return item
    }

    @Test func deletingAPhotoRemovesItsRowAndFile() throws {
        let storage = makeStorage()
        let context = try makeContext()
        let project = Project(name: "Board")
        context.insert(project)
        try storage.write(data: Data("x".utf8), fileName: "a.png", projectID: project.id)
        let photo = makeItem("a.png", kind: .image, project: project, context: context)
        try context.save()

        deleteBoardItems([photo], context: context, storage: storage)

        #expect(try context.fetch(FetchDescriptor<BoardItem>()).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: storage.fileURL(fileName: "a.png", projectID: project.id).path))
    }

    @Test func deletingAPhotoWithAMissingFileStillRemovesIt() throws {
        let context = try makeContext()
        let project = Project(name: "Board")
        context.insert(project)
        let photo = makeItem("gone.png", kind: .image, project: project, context: context)
        try context.save()

        deleteBoardItems([photo], context: context, storage: makeStorage())

        #expect(try context.fetch(FetchDescriptor<BoardItem>()).isEmpty)
    }

    @Test func deletingANoteLeavesOtherItemsAlone() throws {
        let context = try makeContext()
        let project = Project(name: "Board")
        context.insert(project)
        let note = makeItem("", kind: .note, project: project, context: context)
        let photo = makeItem("a.png", kind: .image, project: project, context: context)
        try context.save()

        deleteBoardItems([note], context: context, storage: makeStorage())

        #expect(try context.fetch(FetchDescriptor<BoardItem>()).map(\.id) == [photo.id])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/BoardDeletionTests`
Expected: build FAILS with "cannot find 'deleteBoardItems' in scope".

- [ ] **Step 3: Add `evict` to `moody/Storage/ImageCache.swift`**

Add after `image(for:)`:

```swift

    func evict(fileName: String) {
        cache.removeObject(forKey: fileName as NSString)
    }
```

- [ ] **Step 4: Create `moody/Views/BoardDeletion.swift`**

```swift
//
//  BoardDeletion.swift
//  moody
//
//  Deletes board items: the rows, plus each photo's stored file (cascade
//  delete only removes rows, as with a project's directory). Connectors go
//  with their endpoints by cascade. Toolbar / key action only, never
//  mid-gesture.
//

import Foundation
import OSLog
import SwiftData

private extension Logger {
    static let boardDeletion = Logger(subsystem: Bundle.main.bundleIdentifier ?? "moody", category: "BoardDeletion")
}

func deleteBoardItems(
    _ items: [BoardItem],
    context: ModelContext,
    storage: FileStorageService = FileStorageService(),
    cache: ImageCache = .shared
) {
    let files = items.compactMap { item -> (fileName: String, projectID: UUID)? in
        guard item.kind == .image, let projectID = item.project?.id else { return nil }
        return (item.fileName, projectID)
    }
    for item in items {
        context.delete(item)
    }
    // Save before touching disk: if the save fails the rows stay, and so must their files.
    do {
        try context.save()
    } catch {
        Logger.boardDeletion.error("Failed to delete board items: \(error.localizedDescription, privacy: .public)")
        return
    }
    for file in files {
        cache.evict(fileName: file.fileName)
        do {
            try storage.deleteFile(fileName: file.fileName, projectID: file.projectID)
        } catch {
            Logger.boardDeletion.error("Failed to delete image file: \(error.localizedDescription, privacy: .public)")
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/BoardDeletionTests`
Expected: PASS.

- [ ] **Step 6: Add the ⌫ key monitor to `moody/Views/BoardCanvasView.swift`**

Add the property `let onDeleteKey: () -> Bool` after `let controller: BoardCanvasController`, with doc comment `/// ⌫ / ⌦ on this board's window; returns whether the key was used.`

In `makeNSView`, after `coordinator.attach(to: scrollView)`, add `coordinator.installDeleteKeyMonitor()`. Add to the struct:

```swift
    static func dismantleNSView(_: NSScrollView, coordinator: Coordinator) {
        coordinator.removeDeleteKeyMonitor()
    }
```

In `Coordinator`, add the stored property `private var keyMonitor: Any?` and, under a new `// MARK: - Delete key` section:

```swift
        /// A local monitor rather than .onDeleteCommand: the board's hosting
        /// view sits inside an NSScrollView and is rarely first responder, so a
        /// responder-chain command never reaches it. Text editing keeps the key:
        /// any NSText first responder (field editors, TextEditor's text view)
        /// wins, so typing in a note, a container title or the sidebar is safe.
        func installDeleteKeyMonitor() {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      [51, 117].contains(event.keyCode), // delete, forward delete
                      event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
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
```

If the compiler flags the handler as non-isolated, wrap its body in `MainActor.assumeIsolated { ... }` (local monitors run on the main thread).

- [ ] **Step 7: Wire Delete into `moody/Views/BoardView.swift`**

Add state: `@State private var isConfirmingDelete = false`.

Add helpers:

```swift
    private var selectedImages: [BoardItem] {
        selectedItems.filter { $0.kind == .image }
    }

    /// ⌫ and the toolbar Delete button. Photos lose their file with no undo,
    /// so only those ask first.
    private func handleDeleteKey() -> Bool {
        guard !selectedItems.isEmpty else { return false }
        if selectedImages.isEmpty {
            deleteSelection()
        } else {
            isConfirmingDelete = true
        }
        return true
    }

    private func deleteSelection() {
        let targets = selectedItems
        selectedItemIDs = []
        deleteBoardItems(targets, context: modelContext)
    }
```

Pass `onDeleteKey: handleDeleteKey` as the last `BoardCanvasView(...)` argument.

In the selection `else` branch of the toolbar, after the Download Selected item, add:

```swift
                ToolbarItem(placement: .primaryAction) {
                    Button("Delete", systemImage: "trash") {
                        _ = handleDeleteKey()
                    }
                    .help("Delete (⌫)")
                }
```

Add the alert after the existing `.alert`:

```swift
        .alert(
            selectedItems.count == 1 ? "Delete 1 item?" : "Delete \(selectedItems.count) items?",
            isPresented: $isConfirmingDelete
        ) {
            Button("Delete", role: .destructive, action: deleteSelection)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Photos are removed from the board and from disk. This can't be undone.")
        }
```

Download only copies photos. In `download(_:)` replace `targets.map(\.fileName)` with `targets.filter { $0.kind == .image }.map(\.fileName)`. Change Download All's `.disabled(items.isEmpty)` to `.disabled(!items.contains { $0.kind == .image })`. Change Download Selected's help to use `selectedImages.count` and add `.disabled(selectedImages.isEmpty)`.

- [ ] **Step 8: Only photos load images — `moody/Views/BoardItemView.swift`**

Change the `.task` to:

```swift
            .task(id: item.fileName) {
                guard item.kind == .image else { return }
                image = ImageCache.shared.image(for: item)
            }
```

- [ ] **Step 9: Build, full tests, lint**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' && swiftformat . && swiftlint lint --strict`
Expected: all PASS, no violations.

- [ ] **Step 10: Manual QA**

Run the app (Xcode ⌘R). On a board with photos:
1. Select one photo and press ⌫: the alert appears. Cancel keeps it; Delete removes it. Check the file is gone from `~/Library/Containers/<bundle>/Data/Library/Application Support/Moody/Projects/<id>/images/`.
2. Marquee-select two photos, click the toolbar trash, and confirm: both are gone.
3. Select a photo, then double-click a board in the sidebar to rename it and press ⌫ in the field: only the text changes and the photo stays (Review Focus 1).

---

# Phase 1 — Notes

### Task 3: Note geometry and factory

**Files:**
- Create: `moody/Views/Annotations/NoteGeometry.swift`
- Create: `moody/Views/Annotations/BoardItemFactories.swift`
- Test: `moodyTests/NoteGeometryTests.swift`

**Interfaces:**
- Consumes: `BoardItem(…, kind:)`, `resolvedColor` (Task 1).
- Produces: `enum NoteMetrics { width = 220, padding = 12, minHeight = 80, fontSize = 14, editorInset = 5 }`; `func noteHeight(text: String, width: Double = NoteMetrics.width) -> Double`; `func fitNoteHeight(_ note: BoardItem)` (keeps the top edge fixed); `extension BoardItem { static func note(at: CGPoint, zIndex: Int, project: Project) -> BoardItem }`.

- [ ] **Step 1: Write the failing test**

Create `moodyTests/NoteGeometryTests.swift`:

```swift
//
//  NoteGeometryTests.swift
//  moodyTests
//

import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import moody

struct NoteGeometryTests {
    @Test func emptyNoteUsesTheMinimumHeight() {
        #expect(noteHeight(text: "") == NoteMetrics.minHeight)
    }

    @Test func longTextGrowsPastTheMinimum() {
        let text = String(repeating: "Warm stone and long shadows. ", count: 20)
        #expect(noteHeight(text: text) > NoteMetrics.minHeight)
    }

    @Test func moreTextIsNeverShorter() {
        let short = String(repeating: "word ", count: 30)
        #expect(noteHeight(text: short + short) >= noteHeight(text: short))
    }

    @Test func fittingANoteKeepsItsTopEdge() throws {
        let schema = Schema([Project.self, BoardItem.self, BoardConnector.self])
        let context = ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
        let project = Project(name: "Board")
        context.insert(project)
        let note = BoardItem.note(at: CGPoint(x: 0, y: 100), zIndex: 1, project: project)
        context.insert(note)
        let top = note.positionY - note.height / 2

        note.text = String(repeating: "Warm stone and long shadows. ", count: 20)
        fitNoteHeight(note)

        #expect(note.height > NoteMetrics.minHeight)
        #expect(abs((note.positionY - note.height / 2) - top) < 0.001)
    }

    @Test func noteFactoryMakesAYellowNoteCard() throws {
        let project = Project(name: "Board")
        let note = BoardItem.note(at: CGPoint(x: 5, y: 6), zIndex: 3, project: project)
        #expect(note.kind == .note)
        #expect(note.width == NoteMetrics.width)
        #expect(note.height == NoteMetrics.minHeight)
        #expect(note.resolvedColor == .yellow)
        #expect(note.fileName.isEmpty)
        #expect(note.positionX == 5)
        #expect(note.zIndex == 3)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/NoteGeometryTests`
Expected: build FAILS with "cannot find 'noteHeight' in scope".

- [ ] **Step 3: Create `moody/Views/Annotations/NoteGeometry.swift`**

```swift
//
//  NoteGeometry.swift
//  moody
//
//  Sizing for note cards: fixed width, height fitted to the text.
//

import AppKit

enum NoteMetrics {
    static let width: Double = 220
    static let padding: Double = 12
    static let minHeight: Double = 80
    static let fontSize: Double = 14
    /// TextEditor's line-fragment padding on each side; NoteCardView pads
    /// static text by the same amount so it doesn't shift when editing starts.
    static let editorInset: Double = 5
}

/// Card height that fits `text` wrapped at `width`, never below `NoteMetrics.minHeight`.
func noteHeight(text: String, width: Double = NoteMetrics.width) -> Double {
    let textWidth = width - 2 * (NoteMetrics.padding + NoteMetrics.editorInset)
    let bounds = NSAttributedString(
        string: text,
        attributes: [.font: NSFont.systemFont(ofSize: NoteMetrics.fontSize)]
    ).boundingRect(
        with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    return max(NoteMetrics.minHeight, ceil(bounds.height) + 2 * NoteMetrics.padding + 2 * NoteMetrics.editorInset)
}

/// Resizes `note` to fit its text, growing downward (top edge fixed). Caller saves.
func fitNoteHeight(_ note: BoardItem) {
    let top = note.positionY - note.height / 2
    note.height = noteHeight(text: note.text, width: note.width)
    note.positionY = top + note.height / 2
}
```

- [ ] **Step 4: Create `moody/Views/Annotations/BoardItemFactories.swift`**

```swift
//
//  BoardItemFactories.swift
//  moody
//
//  New non-photo board items. Callers insert and save.
//

import CoreGraphics
import Foundation

extension BoardItem {
    static func note(at center: CGPoint, zIndex: Int, project: Project) -> BoardItem {
        BoardItem(
            fileName: "",
            positionX: center.x,
            positionY: center.y,
            width: NoteMetrics.width,
            height: NoteMetrics.minHeight,
            pixelWidth: 0,
            pixelHeight: 0,
            zIndex: zIndex,
            kind: .note,
            project: project
        )
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/NoteGeometryTests`
Expected: PASS.

- [ ] **Step 6: Lint**

Run: `swiftformat . && swiftlint lint --strict`
Expected: no violations.

---

### Task 4: Add menu, note cards on the board

**Files:**
- Modify: `moody/Views/BoardCanvasView.swift` (`BoardCanvasController.visibleCenter`, `Coordinator.visibleCenter()`)
- Create: `moody/Views/Annotations/NoteCardView.swift`
- Modify: `moody/Views/BoardItemView.swift` (body switches on kind)
- Modify: `moody/Views/BoardView.swift` (Add menu, `addNote()`)

**Interfaces:**
- Consumes: `BoardItem.note(at:zIndex:project:)`, `NoteMetrics` (Task 3); `nextZIndex(existing:)` (`moody/Import/ImportGeometry.swift`).
- Produces: `BoardCanvasController.visibleCenter: () -> CGPoint`; `NoteCardView(item:)` (Task 5 extends its init); `BoardView.addNote()`.

- [ ] **Step 1: Expose the viewport center in `moody/Views/BoardCanvasView.swift`**

In `BoardCanvasController` add:

```swift
    /// Board-space center of what's on screen, where new notes and containers land.
    var visibleCenter: () -> CGPoint = { .zero }
```

In `makeNSView` after the `controller.zoomToFit = …` line add:

```swift
        controller.visibleCenter = { [weak coordinator] in coordinator?.visibleCenter() ?? .zero }
```

In `Coordinator`, after `zoomToFit()`:

```swift
        func visibleCenter() -> CGPoint {
            let visible = currentVisibleRect()
            return CGPoint(x: visible.midX, y: visible.midY)
        }
```

- [ ] **Step 2: Create `moody/Views/Annotations/NoteCardView.swift` (display only)**

```swift
//
//  NoteCardView.swift
//  moody
//
//  A sticky-note card: the note's text on a pastel of its FolderColor.
//  Dark text on a light card regardless of the board's background.
//

import SwiftUI

struct NoteCardView: View {
    let item: BoardItem

    var body: some View {
        Text(item.text.isEmpty ? "Note" : item.text)
            .foregroundStyle(Color.black.opacity(item.text.isEmpty ? 0.35 : 0.85))
            .padding(.horizontal, NoteMetrics.editorInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .font(.system(size: NoteMetrics.fontSize))
            .padding(NoteMetrics.padding)
            .background(card)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 6).fill(item.resolvedColor.color.opacity(0.35)))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
    }
}
```

- [ ] **Step 3: Switch `BoardItemView` on kind**

In `moody/Views/BoardItemView.swift` rename the existing `content` property to `imageContent`, then add:

```swift
    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .image: imageContent
        case .note: NoteCardView(item: item)
        case .container: Color.clear // ContainerView arrives in Task 8
        }
    }
```

Update the file header's first line to: `//  One placed board item (photo, note or container): renders at its stored position/size, and`.

- [ ] **Step 4: Add the Add menu to `moody/Views/BoardView.swift`**

As the first item inside `.toolbar { … }`:

```swift
            ToolbarItem(placement: .primaryAction) {
                // One menu, like the sidebar's "New": separate buttons overflow the toolbar.
                Menu {
                    Button("Note", systemImage: "note.text", action: addNote)
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .help("Add Note or Container")
            }
```

Add the action:

```swift
    private func addNote() {
        let note = BoardItem.note(
            at: canvasController.visibleCenter(),
            zIndex: nextZIndex(existing: items.map(\.zIndex)),
            project: project
        )
        modelContext.insert(note)
        try? modelContext.save()
        selectedItemIDs = [note.id]
    }
```

- [ ] **Step 5: Build, tests, lint**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' && swiftformat . && swiftlint lint --strict`
Expected: PASS, no violations.

- [ ] **Step 6: Manual QA**

Run the app. Click Add ▸ Note: a yellow "Note" card appears at the center of the viewport, selected. Drag it, marquee-select it with a photo, align them, zoom to fit (it's included), then ⌫ deletes it with no alert. Repeat at zoom 50% and 200%.

---

### Task 5: Note editing and color

**Files:**
- Modify: `moody/Views/BoardView.swift` (`editingItemID` state, `addNote` enters editing, canvas call site)
- Modify: `moody/Views/BoardCanvasView.swift` (`@Binding var editingItemID`, `makeContent`)
- Modify: `moody/Views/BoardDocumentContentView.swift` (`@Binding var editingItemID`, double-click, end editing)
- Modify: `moody/Views/BoardItemView.swift` (`isEditing`, `onEndEditing`, gesture masking)
- Modify: `moody/Views/Annotations/NoteCardView.swift` (TextEditor, color menu)

**Interfaces:**
- Consumes: `fitNoteHeight(_:)` (Task 3), `NoteCardView` (Task 4).
- Produces: `BoardView.editingItemID: UUID?` passed as a binding through `BoardCanvasView.editingItemID` (declared after `selectedItemIDs`) to `BoardDocumentContentView.editingItemID` (declared after `selectedItemIDs`); `BoardItemView` properties in order: `item, canvasOrigin, isSelected, isEditing, liveTranslation, onDragChanged, onDragEnded, onEndEditing`; `NoteCardView(item:isEditing:onEndEditing:)`; `BoardDocumentContentView.endEditing()`.

Editing writes `item.text` live through a binding (typing is not a gesture, so invariant 2 holds) and saves once when editing ends. Every way of ending (Esc, focus loss, clicking another item or the canvas) goes through `endEditing()`.

- [ ] **Step 1: Plumb `editingItemID`**

`BoardView`: add `@State private var editingItemID: UUID?` with doc comment `/// The note or container whose text is being edited. Ephemeral.` Pass `editingItemID: $editingItemID` after `selectedItemIDs:` in the `BoardCanvasView(...)` call. At the end of `addNote()` add `editingItemID = note.id`.

`BoardCanvasView`: add `@Binding var editingItemID: UUID?` after `selectedItemIDs`. In `makeContent()` pass `editingItemID: parent.$editingItemID` after `selectedItemIDs:`.

`BoardDocumentContentView`: add `@Binding var editingItemID: UUID?` after `selectedItemIDs`, with doc comment `/// See BoardView. Typing writes the model live; endEditing() saves.`

- [ ] **Step 2: `BoardItemView` editing parameters**

Add `let isEditing: Bool` after `isSelected` and `let onEndEditing: () -> Void` after `onDragEnded`. Change `.gesture(dragGesture)` to:

```swift
            // While editing, clicks belong to the text view, not the move/select gesture.
            .gesture(dragGesture, including: isEditing ? .subviews : .all)
```

and the note case to `case .note: NoteCardView(item: item, isEditing: isEditing, onEndEditing: onEndEditing)`.

- [ ] **Step 3: `BoardDocumentContentView` double-click and end editing**

In the `ForEach`, pass `isEditing: editingItemID == item.id` after `isSelected:` and `onEndEditing: endEditing` after `onDragEnded:`.

Add:

```swift
    /// Single exit for text editing (Esc, focus loss, clicking elsewhere).
    private func endEditing() {
        guard editingItemID != nil else { return }
        editingItemID = nil
        try? modelContext.save()
    }
```

In `handleItemDragChanged`, inside `if activeDragItemID == nil {`, add first:

```swift
            if editingItemID != itemID {
                endEditing()
            }
```

In `marqueeGesture`'s `.onChanged`, add `endEditing()` as the first line.

In `handleItemDragEnded`, extend the zero-translation branch:

```swift
        if translation == .zero, let clicked = activeDragItemID {
            selectedItemIDs = [clicked]
            // The item's only gesture is this zero-distance drag, so a
            // double-click is read from the event instead of a competing
            // TapGesture(count: 2) that would delay single-click selection.
            if NSApp.currentEvent?.clickCount == 2, items.first(where: { $0.id == clicked })?.kind != .image {
                editingItemID = clicked
            }
        }
```

- [ ] **Step 4: `NoteCardView` editing and color**

Replace `moody/Views/Annotations/NoteCardView.swift`'s struct with:

```swift
struct NoteCardView: View {
    @Bindable var item: BoardItem
    let isEditing: Bool
    let onEndEditing: () -> Void

    @Environment(\.modelContext) private var modelContext
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextEditor(text: $item.text)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(Color.black.opacity(0.85))
                    .focused($isFocused)
                    .onExitCommand(perform: onEndEditing)
                    .onChange(of: isFocused) { _, focused in
                        if !focused {
                            onEndEditing()
                        }
                    }
                    .onChange(of: item.text) { fitNoteHeight(item) }
                    .task { await claimFocus() }
            } else {
                Text(item.text.isEmpty ? "Note" : item.text)
                    .foregroundStyle(Color.black.opacity(item.text.isEmpty ? 0.35 : 0.85))
                    .padding(.horizontal, NoteMetrics.editorInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .font(.system(size: NoteMetrics.fontSize))
        .padding(NoteMetrics.padding)
        .background(card)
        .contextMenu {
            Picker("Color", selection: colorBinding) {
                ForEach(FolderColor.allCases) { color in
                    Text(color.displayName).tag(color)
                }
            }
        }
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 6).fill(item.resolvedColor.color.opacity(0.35)))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
    }

    /// A context-menu click, never mid-gesture, so saving here is safe.
    private var colorBinding: Binding<FolderColor> {
        Binding(
            get: { item.resolvedColor },
            set: { color in
                item.colorName = color.rawValue
                try? modelContext.save()
            }
        )
    }

    /// The double-click that started editing is still being handled when the
    /// editor appears, so one focus request can be dropped (same as
    /// InlineRenameField): keep asking until it lands.
    private func claimFocus() async {
        for _ in 0 ..< 20 where !isFocused && isEditing {
            isFocused = true
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
```

The `.onChange(of: isFocused)` only fires on a real change (true → false), so a focus request that hasn't landed yet never ends editing early.

- [ ] **Step 5: Build, tests, lint**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' && swiftformat . && swiftlint lint --strict`
Expected: PASS, no violations.

- [ ] **Step 6: Manual QA (zoom 100% and 200%)**

1. Add ▸ Note: the card opens for editing with a caret. Type four lines: the card grows downward and its top stays put. Press ⌫ while typing: only text is deleted and the note stays (Review Focus 1).
2. Press Esc: editing ends. Relaunch the app: the text persisted.
3. Single-click selects and drag moves, with no lag. Double-click reopens editing. Clicking the canvas or another photo ends editing.
4. Right-click ▸ Color ▸ Blue tints the card. Switch the board to Dark Background: the text stays readable.

---

# Phase 2 — Containers

### Task 6: Pure stack layout, insertion index, hit-test, container expansion

**Files:**
- Create: `moody/Views/Annotations/ContainerLayout.swift`
- Modify: `moody/Views/BoardSelectionGeometry.swift` (add `expandingContainers`)
- Test: `moodyTests/ContainerLayoutTests.swift`

**Interfaces:**
- Consumes: `StackAxis` (Task 1).
- Produces: `enum StackMetrics { headerHeight = 32, padding = 12, gap = 12, minSize = 240×160 }`; `func stackLayout(axis: StackAxis, topLeft: CGPoint, sizes: [CGSize]) -> (centers: [CGPoint], size: CGSize)`; `func stackInsertionIndex(axis: StackAxis, point: CGPoint, existingCenters: [CGPoint]) -> Int`; `func topmostContaining(_ point: CGPoint, items: [(id: UUID, center: CGPoint, size: CGSize)]) -> UUID?` (items back-to-front); `func expandingContainers(_ ids: Set<UUID>, children: [UUID: [UUID]]) -> Set<UUID>`.

- [ ] **Step 1: Write the failing test**

Create `moodyTests/ContainerLayoutTests.swift`:

```swift
//
//  ContainerLayoutTests.swift
//  moodyTests
//

import CoreGraphics
import Foundation
import Testing
@testable import moody

struct ContainerLayoutTests {
    // MARK: - stackLayout

    @Test func emptyContainerHasTheMinimumSize() {
        let layout = stackLayout(axis: .column, topLeft: .zero, sizes: [])
        #expect(layout.centers.isEmpty)
        #expect(layout.size == StackMetrics.minSize)
    }

    @Test func columnStacksBelowTheHeaderCenteredHorizontally() {
        let layout = stackLayout(axis: .column, topLeft: .zero, sizes: [
            CGSize(width: 100, height: 50),
            CGSize(width: 300, height: 200),
        ])
        // width = 300 + 2*12, height = 32 + 2*12 + 50 + 12 + 200
        #expect(layout.size == CGSize(width: 324, height: 318))
        #expect(layout.centers == [CGPoint(x: 162, y: 69), CGPoint(x: 162, y: 206)])
    }

    @Test func rowStacksLeftToRightCenteredInTheContentBand() {
        let layout = stackLayout(axis: .row, topLeft: .zero, sizes: [
            CGSize(width: 100, height: 50),
            CGSize(width: 60, height: 80),
        ])
        // width = max(240, 12 + 100 + 12 + 60 + 12), height = max(160, 32 + 24 + 80)
        #expect(layout.size == CGSize(width: 240, height: 160))
        #expect(layout.centers == [CGPoint(x: 62, y: 96), CGPoint(x: 154, y: 96)])
    }

    @Test func layoutIsRelativeToTheTopLeft() {
        let layout = stackLayout(axis: .column, topLeft: CGPoint(x: 1000, y: -500), sizes: [CGSize(width: 100, height: 50)])
        #expect(layout.centers == [CGPoint(x: 1120, y: -431)])
    }

    // MARK: - stackInsertionIndex

    @Test func insertionIndexCountsChildrenBeforeThePointAlongTheAxis() {
        let centers = [CGPoint(x: 0, y: 100), CGPoint(x: 0, y: 200), CGPoint(x: 0, y: 300)]
        #expect(stackInsertionIndex(axis: .column, point: CGPoint(x: 0, y: 50), existingCenters: centers) == 0)
        #expect(stackInsertionIndex(axis: .column, point: CGPoint(x: 0, y: 250), existingCenters: centers) == 2)
        #expect(stackInsertionIndex(axis: .column, point: CGPoint(x: 0, y: 900), existingCenters: centers) == 3)
        #expect(stackInsertionIndex(axis: .row, point: CGPoint(x: 50, y: 900), existingCenters: centers) == 3)
    }

    // MARK: - topmostContaining

    @Test func topmostContainingPicksTheFrontMostHit() {
        let back = UUID()
        let front = UUID()
        let items = [
            (id: back, center: CGPoint(x: 0, y: 0), size: CGSize(width: 100, height: 100)),
            (id: front, center: CGPoint(x: 20, y: 0), size: CGSize(width: 100, height: 100)),
        ]
        #expect(topmostContaining(CGPoint(x: 10, y: 0), items: items) == front)
        #expect(topmostContaining(CGPoint(x: -45, y: 0), items: items) == back)
        #expect(topmostContaining(CGPoint(x: 500, y: 0), items: items) == nil)
    }

    // MARK: - expandingContainers

    @Test func expandingAContainerAddsItsStackedPhotos() {
        let container = UUID()
        let photo = UUID()
        let loose = UUID()
        #expect(expandingContainers([container, loose], children: [container: [photo]]) == [container, photo, loose])
        #expect(expandingContainers([], children: [container: [photo]]).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/ContainerLayoutTests`
Expected: build FAILS with "cannot find 'stackLayout' in scope".

- [ ] **Step 3: Create `moody/Views/Annotations/ContainerLayout.swift`**

```swift
//
//  ContainerLayout.swift
//  moody
//
//  Pure geometry for container stacks: photos keep their own size and sit
//  edge to edge below a header band, centered on the cross axis.
//

import CoreGraphics
import Foundation

enum StackMetrics {
    static let headerHeight: Double = 32
    static let padding: Double = 12
    static let gap: Double = 12
    static let minSize = CGSize(width: 240, height: 160)
}

/// Child centers and container size for a stack whose top-left is `topLeft`.
func stackLayout(axis: StackAxis, topLeft: CGPoint, sizes: [CGSize]) -> (centers: [CGPoint], size: CGSize) {
    let pad = StackMetrics.padding
    let header = StackMetrics.headerHeight
    let spacing = StackMetrics.gap * Double(max(sizes.count - 1, 0))
    var centers: [CGPoint] = []
    switch axis {
    case .column:
        let width = max(StackMetrics.minSize.width, (sizes.map(\.width).max() ?? 0) + 2 * pad)
        let height = max(StackMetrics.minSize.height, header + 2 * pad + sizes.map(\.height).reduce(0, +) + spacing)
        var y = topLeft.y + header + pad
        for size in sizes {
            centers.append(CGPoint(x: topLeft.x + width / 2, y: y + size.height / 2))
            y += size.height + StackMetrics.gap
        }
        return (centers, CGSize(width: width, height: height))
    case .row:
        let width = max(StackMetrics.minSize.width, 2 * pad + sizes.map(\.width).reduce(0, +) + spacing)
        let height = max(StackMetrics.minSize.height, header + 2 * pad + (sizes.map(\.height).max() ?? 0))
        let midY = topLeft.y + header + (height - header) / 2
        var x = topLeft.x + pad
        for size in sizes {
            centers.append(CGPoint(x: x + size.width / 2, y: midY))
            x += size.width + StackMetrics.gap
        }
        return (centers, CGSize(width: width, height: height))
    }
}

/// Where a photo released at `point` goes in a stack: the number of existing
/// children whose center lies before it along the axis.
func stackInsertionIndex(axis: StackAxis, point: CGPoint, existingCenters: [CGPoint]) -> Int {
    existingCenters.filter { axis == .column ? $0.y < point.y : $0.x < point.x }.count
}

/// Id of the front-most item containing `point`; `items` are ordered back to front.
func topmostContaining(_ point: CGPoint, items: [(id: UUID, center: CGPoint, size: CGSize)]) -> UUID? {
    items.last { item in
        CGRect(
            x: item.center.x - item.size.width / 2,
            y: item.center.y - item.size.height / 2,
            width: item.size.width,
            height: item.size.height
        ).contains(point)
    }?.id
}
```

- [ ] **Step 4: Add `expandingContainers` to `moody/Views/BoardSelectionGeometry.swift`**

Append:

```swift

/// `ids` plus every photo stacked in a container among them (`children`
/// maps container id → stacked photo ids), so dragging a container carries
/// its stack.
func expandingContainers(_ ids: Set<UUID>, children: [UUID: [UUID]]) -> Set<UUID> {
    ids.union(ids.flatMap { children[$0] ?? [] })
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/ContainerLayoutTests`
Expected: PASS.

- [ ] **Step 6: Lint**

Run: `swiftformat . && swiftlint lint --strict`
Expected: no violations.

---

### Task 7: Stack model writes, container factory, delete relayout

**Files:**
- Create: `moody/Views/Annotations/ContainerStacking.swift`
- Modify: `moody/Views/Annotations/BoardItemFactories.swift` (container factory)
- Modify: `moody/Views/BoardDeletion.swift` (relayout containers that lost a photo)
- Test: `moodyTests/ContainerStackingTests.swift`

**Interfaces:**
- Consumes: `stackLayout`, `stackInsertionIndex`, `StackMetrics` (Task 6); `nextZIndex(existing:)`; `deleteBoardItems` (Task 2).
- Produces: `func relayout(_ container: BoardItem, children: [BoardItem]? = nil)`; `func insertIntoStack(_ items: [BoardItem], container: BoardItem, at index: Int, allZIndices: [Int])` (index clamped, so `Int.max` appends); `func removeFromStack(_ items: [BoardItem])`; `func commitStackDrop(movingItems: [BoardItem], target: BoardItem?, dragged: BoardItem?, allZIndices: [Int])`; `extension BoardItem { static func container(axis: StackAxis, at: CGPoint, zIndex: Int, project: Project) -> BoardItem }`.

Functions that change membership pass explicit `children` to `relayout`, so they don't depend on when SwiftData updates the `stackedItems` inverse.

- [ ] **Step 1: Write the failing test**

Create `moodyTests/ContainerStackingTests.swift`:

```swift
//
//  ContainerStackingTests.swift
//  moodyTests
//

import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import moody

@MainActor
struct ContainerStackingTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Project.self, BoardItem.self, BoardConnector.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    /// An empty column container whose top-left is (0, 0).
    private func makeContainer(_ project: Project, _ context: ModelContext, axis: StackAxis = .column) -> BoardItem {
        let container = BoardItem.container(axis: axis, at: CGPoint(x: 120, y: 80), zIndex: 1, project: project)
        context.insert(container)
        return container
    }

    private func makePhoto(_ project: Project, _ context: ModelContext, width: Double = 100, height: Double = 50,
                           at center: CGPoint = CGPoint(x: 900, y: 900), zIndex: Int = 2) -> BoardItem {
        let photo = BoardItem(
            fileName: "\(UUID().uuidString).png", positionX: center.x, positionY: center.y, width: width, height: height,
            pixelWidth: Int(width), pixelHeight: Int(height), zIndex: zIndex, project: project
        )
        context.insert(photo)
        return photo
    }

    private func setUp() throws -> (ModelContext, Project) {
        let context = try makeContext()
        let project = Project(name: "Board")
        context.insert(project)
        return (context, project)
    }

    @Test func containerFactoryMakesAnEmptyBlueStack() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context, axis: .row)
        #expect(container.kind == .container)
        #expect(container.axis == .row)
        #expect(container.size == StackMetrics.minSize)
        #expect(container.resolvedColor == FolderColor.defaultColor)
    }

    @Test func insertingIntoAnEmptyColumnStacksBelowTheHeader() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context)
        let photo = makePhoto(project, context)

        insertIntoStack([photo], container: container, at: 0, allZIndices: [1, 2])

        #expect(photo.container?.id == container.id)
        #expect(photo.center == CGPoint(x: 120, y: 69))
        #expect(container.size == StackMetrics.minSize)
    }

    @Test func insertedPhotosComeInFrontOfEverything() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context)
        let photo = makePhoto(project, context, zIndex: 2)

        insertIntoStack([photo], container: container, at: 0, allZIndices: [1, 2, 7])

        #expect(photo.zIndex == 8)
    }

    @Test func insertingAtAnIndexOrdersTheStack() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context)
        let a = makePhoto(project, context)
        let b = makePhoto(project, context)
        let c = makePhoto(project, context)
        insertIntoStack([a, b], container: container, at: 0, allZIndices: [])

        insertIntoStack([c], container: container, at: 1, allZIndices: [])

        #expect([a.stackOrder, c.stackOrder, b.stackOrder] == [0, 1, 2])
        #expect(a.positionY < c.positionY)
        #expect(c.positionY < b.positionY)
    }

    @Test func reinsertingAtItsOwnIndexKeepsTheOrder() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context)
        let a = makePhoto(project, context)
        let b = makePhoto(project, context)
        insertIntoStack([a, b], container: container, at: 0, allZIndices: [])

        insertIntoStack([a], container: container, at: 0, allZIndices: [])

        #expect([a.stackOrder, b.stackOrder] == [0, 1])
    }

    @Test func theContainerGrowsDownwardKeepingItsTopLeft() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context)
        let tall = makePhoto(project, context, width: 100, height: 300)

        insertIntoStack([tall], container: container, at: 0, allZIndices: [])

        #expect(container.height == 32 + 24 + 300)
        #expect(container.positionY - container.height / 2 == 0)
        #expect(container.positionX - container.width / 2 == 0)
    }

    @Test func removingFromAStackKeepsThePhotoWhereItIsAndClosesTheGap() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context)
        let a = makePhoto(project, context)
        let b = makePhoto(project, context)
        insertIntoStack([a, b], container: container, at: 0, allZIndices: [])
        let firstSlot = a.center
        a.positionX = 2000

        removeFromStack([a])

        #expect(a.container == nil)
        #expect(a.positionX == 2000)
        #expect(b.center == firstSlot)
        #expect(b.stackOrder == 0)
    }

    @Test func droppingALoosePhotoOnAContainerStacksItAtTheDropPosition() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context)
        let a = makePhoto(project, context)
        let b = makePhoto(project, context)
        insertIntoStack([a, b], container: container, at: 0, allZIndices: [])
        let loose = makePhoto(project, context, at: CGPoint(x: 120, y: a.positionY + 1))

        commitStackDrop(movingItems: [loose], target: container, dragged: loose, allZIndices: [])

        #expect([a.stackOrder, loose.stackOrder, b.stackOrder] == [0, 1, 2])
    }

    @Test func draggingAStackedPhotoOutRemovesIt() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context)
        let photo = makePhoto(project, context)
        insertIntoStack([photo], container: container, at: 0, allZIndices: [])

        commitStackDrop(movingItems: [photo], target: nil, dragged: photo, allZIndices: [])

        #expect(photo.container == nil)
    }

    @Test func draggingAContainerWithItsPhotosKeepsThemStacked() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context)
        let photo = makePhoto(project, context)
        insertIntoStack([photo], container: container, at: 0, allZIndices: [])

        commitStackDrop(movingItems: [container, photo], target: nil, dragged: container, allZIndices: [])

        #expect(photo.container?.id == container.id)
    }

    @Test func movingAPhotoBetweenContainersRelayoutsBoth() throws {
        let (context, project) = try setUp()
        let left = makeContainer(project, context)
        let right = BoardItem.container(axis: .column, at: CGPoint(x: 1120, y: 80), zIndex: 1, project: project)
        context.insert(right)
        let a = makePhoto(project, context)
        let b = makePhoto(project, context)
        insertIntoStack([a, b], container: left, at: 0, allZIndices: [])
        let firstSlot = a.center

        insertIntoStack([a], container: right, at: 0, allZIndices: [])

        #expect(a.container?.id == right.id)
        #expect(a.positionX == 1120)
        #expect(b.center == firstSlot)
    }

    @Test func deletingAContainerLeavesItsPhotosLooseAndDropsItsConnectors() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context)
        let photo = makePhoto(project, context)
        insertIntoStack([photo], container: container, at: 0, allZIndices: [])
        context.insert(BoardConnector(from: photo, to: container))
        try context.save()
        let position = photo.center

        deleteBoardItems([container], context: context)

        #expect(try context.fetch(FetchDescriptor<BoardItem>()).map(\.id) == [photo.id])
        #expect(photo.container == nil)
        #expect(photo.center == position)
        #expect(try context.fetch(FetchDescriptor<BoardConnector>()).isEmpty)
    }

    @Test func deletingAStackedPhotoClosesTheGap() throws {
        let (context, project) = try setUp()
        let container = makeContainer(project, context)
        let a = makePhoto(project, context)
        let b = makePhoto(project, context)
        insertIntoStack([a, b], container: container, at: 0, allZIndices: [])
        try context.save()
        let firstSlot = a.center
        let storage = FileStorageService(rootDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("moody-tests-\(UUID().uuidString)", isDirectory: true))

        deleteBoardItems([a], context: context, storage: storage)

        #expect(b.center == firstSlot)
        #expect(b.stackOrder == 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/ContainerStackingTests`
Expected: build FAILS with "type 'BoardItem' has no member 'container(axis:at:zIndex:project:)'".

- [ ] **Step 3: Add the container factory to `BoardItemFactories.swift`**

Inside the extension:

```swift

    static func container(axis: StackAxis, at center: CGPoint, zIndex: Int, project: Project) -> BoardItem {
        let item = BoardItem(
            fileName: "",
            positionX: center.x,
            positionY: center.y,
            width: StackMetrics.minSize.width,
            height: StackMetrics.minSize.height,
            pixelWidth: 0,
            pixelHeight: 0,
            zIndex: zIndex,
            kind: .container,
            project: project
        )
        item.axis = axis
        item.colorName = FolderColor.defaultColor.rawValue
        return item
    }
```

- [ ] **Step 4: Create `moody/Views/Annotations/ContainerStacking.swift`**

```swift
//
//  ContainerStacking.swift
//  moody
//
//  Model writes for container stacks. Like commitGroupMove: callers save
//  afterwards, and only call these from .onEnded, toolbar/menu actions or
//  import, never mid-gesture. Membership changes pass explicit children to
//  relayout so they don't depend on when SwiftData updates `stackedItems`.
//

import CoreGraphics
import Foundation

/// Re-stacks `children` (default: the container's photos) by stackOrder,
/// renumbered 0…n-1, and resizes the container keeping its top-left fixed.
func relayout(_ container: BoardItem, children: [BoardItem]? = nil) {
    let ordered = (children ?? container.stackedItems).sorted { $0.stackOrder < $1.stackOrder }
    let topLeft = CGPoint(x: container.positionX - container.width / 2, y: container.positionY - container.height / 2)
    let layout = stackLayout(axis: container.axis, topLeft: topLeft, sizes: ordered.map(\.size))
    container.width = layout.size.width
    container.height = layout.size.height
    container.positionX = topLeft.x + layout.size.width / 2
    container.positionY = topLeft.y + layout.size.height / 2
    for (index, child) in ordered.enumerated() {
        child.stackOrder = index
        child.positionX = layout.centers[index].x
        child.positionY = layout.centers[index].y
    }
}

/// Stacks `items`, in the given order, into `container` at `index` among its
/// other photos (clamped, so `Int.max` appends), brings them in front of
/// everything, and re-lays out the target and any container they left.
func insertIntoStack(_ items: [BoardItem], container: BoardItem, at index: Int, allZIndices: [Int]) {
    let movingIDs = Set(items.map(\.id))
    let previous = Set(items.compactMap(\.container)).filter { $0.id != container.id }
    var order = container.stackedItems
        .filter { !movingIDs.contains($0.id) }
        .sorted { $0.stackOrder < $1.stackOrder }
    order.insert(contentsOf: items, at: min(max(index, 0), order.count))
    var nextZ = nextZIndex(existing: allZIndices)
    for item in items {
        item.container = container
        item.zIndex = nextZ
        nextZ += 1
    }
    for (position, item) in order.enumerated() {
        item.stackOrder = position
    }
    relayout(container, children: order)
    for old in previous {
        relayout(old, children: old.stackedItems.filter { !movingIDs.contains($0.id) })
    }
}

/// Takes `items` out of their stacks (they stay where they are) and closes
/// the gaps they leave.
func removeFromStack(_ items: [BoardItem]) {
    let ids = Set(items.map(\.id))
    let containers = Set(items.compactMap(\.container))
    for item in items {
        item.container = nil
    }
    for container in containers {
        relayout(container, children: container.stackedItems.filter { !ids.contains($0.id) })
    }
}

/// A finished drag's stack membership, after commitGroupMove has moved the
/// items: photos released over `target` join it, ordered by the drop position
/// of `dragged`; with no target, photos whose container isn't moving with
/// them leave it.
func commitStackDrop(movingItems: [BoardItem], target: BoardItem?, dragged: BoardItem?, allZIndices: [Int]) {
    let movingIDs = Set(movingItems.map(\.id))
    let photos = movingItems.filter { $0.kind == .image }
    guard let target else {
        removeFromStack(photos.filter { photo in photo.container.map { !movingIDs.contains($0.id) } ?? false })
        return
    }
    let axisValue: (BoardItem) -> Double = { target.axis == .column ? $0.positionY : $0.positionX }
    let ordered = photos.sorted { axisValue($0) < axisValue($1) }
    guard let probe = (dragged ?? ordered.first)?.center else { return }
    let others = target.stackedItems.filter { !movingIDs.contains($0.id) }
    let index = stackInsertionIndex(axis: target.axis, point: probe, existingCenters: others.map(\.center))
    insertIntoStack(ordered, container: target, at: index, allZIndices: allZIndices)
}
```

- [ ] **Step 5: Relayout after deletion — `moody/Views/BoardDeletion.swift`**

At the top of `deleteBoardItems`, before `let files`, add:

```swift
    let deletedIDs = Set(items.map(\.id))
    // Containers that lose a photo (and aren't deleted themselves) close the gap.
    let shrinking = Set(items.compactMap(\.container)).filter { !deletedIDs.contains($0.id) }
```

After the `for item in items { context.delete(item) }` loop, before the save, add:

```swift
    for container in shrinking {
        relayout(container, children: container.stackedItems.filter { !deletedIDs.contains($0.id) })
    }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/ContainerStackingTests -only-testing:moodyTests/BoardDeletionTests`
Expected: PASS.

If `deletingAContainerLeavesItsPhotosLooseAndDropsItsConnectors` fails on `photo.container == nil` (nullify only runs at save, which `deleteBoardItems` already does), check that the expectation runs after `deleteBoardItems`. Don't weaken the test.

- [ ] **Step 7: Lint**

Run: `swiftformat . && swiftlint lint --strict`
Expected: no violations.

---

### Task 8: Container view, Add menu entries, rename, appearance, axis switch

**Files:**
- Modify: `moody/Views/Sidebar/FolderAppearancePicker.swift` (bindings instead of `Folder`)
- Modify: `moody/Views/Sidebar/SidebarRows.swift:68`
- Create: `moody/Views/Annotations/ContainerView.swift`
- Modify: `moody/Views/BoardItemView.swift` (`isDropTarget`, container case)
- Modify: `moody/Views/BoardDocumentContentView.swift` (`dropTargetContainerID` state, `isDropTarget` arg, board color scheme)
- Modify: `moody/Views/BoardView.swift` (Add menu entries, `addContainer(_:)`)

**Interfaces:**
- Consumes: `relayout` (Task 7), `BoardItem.container(axis:at:zIndex:project:)` (Task 7), `StackMetrics` (Task 6), `editingItemID` / `endEditing()` / double-click (Task 5).
- Produces: `FolderAppearancePicker(iconName: Binding<String>, colorName: Binding<String>)`; `ContainerView(item:isEditing:isDropTarget:onEndEditing:)`; `BoardItemView` properties in order: `item, canvasOrigin, isSelected, isEditing, isDropTarget, liveTranslation, onDragChanged, onDragEnded, onEndEditing`; `BoardDocumentContentView.dropTargetContainerID: UUID?` (`@State`, set in Task 9).

- [ ] **Step 1: Refactor `FolderAppearancePicker` to bindings**

Replace `@Bindable var folder: Folder` with:

```swift
    @Binding var iconName: String
    @Binding var colorName: String
```

Add:

```swift
    private var selectedColor: FolderColor {
        FolderColor(rawValue: colorName) ?? FolderColor.defaultColor
    }

    private var selectedIcon: String {
        FolderIcon.all.contains(iconName) ? iconName : FolderIcon.defaultName
    }
```

In the body, replace `folder.resolvedColor` with `selectedColor`, `folder.resolvedIconName` with `selectedIcon`, `folder.colorName = folderColor.rawValue` with `colorName = folderColor.rawValue`, and `folder.iconName = iconName` with `self.iconName = iconName`. Update the header comment to: `Popover for choosing a folder's or board container's color and SF Symbol icon from the curated sets in FolderAppearance.swift. Changes apply (and save) immediately.` Preview: `FolderAppearancePicker(iconName: .constant("sparkles"), colorName: .constant("purple"))`.

In `moody/Views/Sidebar/SidebarRows.swift:68` use:

```swift
            FolderAppearancePicker(iconName: Bindable(folder).iconName, colorName: Bindable(folder).colorName)
```

- [ ] **Step 2: Create `moody/Views/Annotations/ContainerView.swift`**

```swift
//
//  ContainerView.swift
//  moody
//
//  A container's frame and header (icon + title). Its photos are ordinary
//  BoardItemViews positioned by relayout; this view only draws behind them.
//  Double-click (handled by the board) renames; right-click changes the
//  appearance or flips the axis.
//

import SwiftData
import SwiftUI

struct ContainerView: View {
    @Bindable var item: BoardItem
    let isEditing: Bool
    let isDropTarget: Bool
    let onEndEditing: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var showsAppearance = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if item.stackedItems.isEmpty {
                Text("Drop photos here")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(item.resolvedColor.color.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: 10).strokeBorder(
                isDropTarget ? Color.accentColor : item.resolvedColor.color.opacity(0.5),
                lineWidth: isDropTarget ? 3 : 1
            )
        )
        .contextMenu {
            Button("Appearance…") { showsAppearance = true }
            Button(item.axis == .column ? "Switch to Row" : "Switch to Column", action: switchAxis)
        }
        .popover(isPresented: $showsAppearance) {
            FolderAppearancePicker(iconName: $item.iconName, colorName: $item.colorName)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: item.resolvedIconName)
                .foregroundStyle(item.resolvedColor.color)
            if isEditing {
                TextField("Untitled", text: $item.title)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit(onEndEditing)
                    .onExitCommand(perform: onEndEditing)
                    .onChange(of: isFocused) { _, focused in
                        if !focused {
                            onEndEditing()
                        }
                    }
                    .task { await claimFocus() }
            } else {
                Text(item.title.isEmpty ? "Untitled" : item.title)
                    .foregroundStyle(item.title.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .font(.headline)
        .padding(.horizontal, StackMetrics.padding)
        .frame(height: StackMetrics.headerHeight)
    }

    /// A context-menu click, never mid-gesture, so writing here is safe.
    private func switchAxis() {
        item.axis = item.axis == .column ? .row : .column
        relayout(item)
        try? modelContext.save()
    }

    /// Same as NoteCardView: the double-click is still being handled when the
    /// field appears, so keep asking for focus until it lands.
    private func claimFocus() async {
        for _ in 0 ..< 20 where !isFocused && isEditing {
            isFocused = true
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
```

- [ ] **Step 3: `BoardItemView` container case**

Add `let isDropTarget: Bool` after `isEditing`. Replace the container case with:

```swift
        case .container:
            ContainerView(item: item, isEditing: isEditing, isDropTarget: isDropTarget, onEndEditing: onEndEditing)
```

- [ ] **Step 4: `BoardDocumentContentView` state and color scheme**

Add:

```swift
    /// The container a release right now would stack the dragged photos into
    /// (highlighted). Live drag state like dragTranslation: never persisted.
    @State private var dropTargetContainerID: UUID?
```

In the `ForEach` pass `isDropTarget: dropTargetContainerID == item.id` after `isEditing:`. On the `ZStack`, right after its closing brace and before `.frame(width: extent.width, …)`, add:

```swift
        // Container headers and hints follow the board's background, not the system appearance.
        .environment(\.colorScheme, project.usesDarkBackground ? .dark : .light)
```

- [ ] **Step 5: Add menu entries in `BoardView`**

In the Add menu after the Note button:

```swift
                    Button("Row Container", systemImage: "rectangle.split.3x1") { addContainer(.row) }
                    Button("Column Container", systemImage: "rectangle.split.1x3") { addContainer(.column) }
```

Add:

```swift
    private func addContainer(_ axis: StackAxis) {
        let container = BoardItem.container(
            axis: axis,
            at: canvasController.visibleCenter(),
            zIndex: nextZIndex(existing: items.map(\.zIndex)),
            project: project
        )
        modelContext.insert(container)
        try? modelContext.save()
        selectedItemIDs = [container.id]
        editingItemID = container.id
    }
```

- [ ] **Step 6: Build, tests, lint**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' && swiftformat . && swiftlint lint --strict`
Expected: PASS, no violations.

- [ ] **Step 7: Manual QA**

1. Add ▸ Column Container: an empty container appears with the title field focused. Type "Geneva" and press Return.
2. Double-click it to rename again; Esc ends editing.
3. Right-click ▸ Appearance…: pick a pin icon and red. The header updates and the change persists after relaunch.
4. Right-click ▸ Switch to Row: still empty, so the size doesn't change.
5. Sidebar folder appearance still works.
6. On a dark board, the header text is light.

---

### Task 9: Drag photos into, within and out of containers; move containers with their stack

**Files:**
- Modify: `moody/Views/BoardDocumentContentView.swift` (moving set, drop target, `handleItemDragEnded`)
- Modify: `moody/Views/BoardView.swift` (`align` skips stacked photos, relayouts containers)

**Interfaces:**
- Consumes: `expandingContainers`, `topmostContaining` (Task 6); `commitStackDrop`, `relayout` (Task 7); `dropTargetContainerID` (Task 8); `BoardItem.center`/`size` (Task 1).
- Produces: nothing new for later tasks. `movingItemIDs` now includes the stacked photos of dragged containers; Task 12 reads it for live connector rects.

- [ ] **Step 1: Moving set carries stacks**

In `BoardDocumentContentView` replace `movingItemIDs` with:

```swift
    /// Ids of items the live drag should move: the whole selection if the
    /// dragged item is a member of a multi-item selection, otherwise just the
    /// dragged item, plus the stacked photos of any container among them.
    private var movingItemIDs: Set<UUID> {
        expandingContainers(itemsToMove(draggedID: activeDragItemID, selection: selectedItemIDs), children: stackChildren)
    }

    /// Container id → ids of the photos stacked in it.
    private var stackChildren: [UUID: [UUID]] {
        items.reduce(into: [:]) { map, item in
            if let containerID = item.container?.id {
                map[containerID, default: []].append(item.id)
            }
        }
    }
```

At the top of the `ZStack { … }` builder add `let moving = movingItemIDs`, and in the `ForEach` replace both `movingItemIDs.contains(item.id)` with `moving.contains(item.id)`. That computes the set once per render instead of twice per item.

- [ ] **Step 2: Live drop target**

Add:

```swift
    /// The front-most container under the dragged item's live center that a
    /// release would stack into. Only photos stack, and a drag that carries a
    /// container never targets one.
    private func stackDropTarget(translation: CGSize) -> UUID? {
        let moving = movingItemIDs
        let movingItems = items.filter { moving.contains($0.id) }
        guard movingItems.contains(where: { $0.kind == .image }),
              !movingItems.contains(where: { $0.kind == .container }),
              let dragged = items.first(where: { $0.id == activeDragItemID })
        else { return nil }
        let probe = CGPoint(x: dragged.positionX + translation.width, y: dragged.positionY + translation.height)
        // items comes from the @Query sorted by zIndex, i.e. back to front.
        let containers = items.filter { $0.kind == .container && !moving.contains($0.id) }
        return topmostContaining(probe, items: containers.map { (id: $0.id, center: $0.center, size: $0.size) })
    }
```

In `handleItemDragChanged`, after `dragTranslation = translation`, add `dropTargetContainerID = stackDropTarget(translation: translation)`.

- [ ] **Step 3: Commit stack membership on release**

Replace the body of `handleItemDragEnded` after the zero-translation `if` block with:

```swift
        let movingItems = items.filter { movingItemIDs.contains($0.id) }
        let target = dropTargetContainerID.flatMap { id in items.first { $0.id == id } }
        let dragged = items.first { $0.id == activeDragItemID }
        let allZIndices = items.map(\.zIndex)
        commitGroupMove(movingItems: movingItems, allZIndices: allZIndices, translation: translation)
        // A click (no movement) never changes stack membership or order.
        if translation != .zero {
            commitStackDrop(movingItems: movingItems, target: target, dragged: dragged, allZIndices: allZIndices)
        }
        try? modelContext.save()
        activeDragItemID = nil
        dragTranslation = .zero
        dropTargetContainerID = nil
        updateCursor()
```

`commitGroupMove` re-assigns z-indices to the moving group in their current relative order. A container always sits below its photos, so it stays below them after a group move.

- [ ] **Step 4: Alignment skips stacked photos — `BoardView.align`**

Replace `let targets = selectedItems` with:

```swift
        // Stacked photos follow their container; aligning them alone would be undone by relayout.
        let targets = selectedItems.filter { $0.container == nil }
```

Before `try? modelContext.save()` in `align` add:

```swift
        for container in targets where container.kind == .container {
            relayout(container)
        }
```

Change the alignment buttons' `.disabled(selectedItems.count < 2)` to `.disabled(selectedItems.count(where: { $0.container == nil }) < 2)`.

- [ ] **Step 5: Build, tests, lint**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' && swiftformat . && swiftlint lint --strict`
Expected: PASS, no violations. If `BoardDocumentContentView` crosses swiftlint's 400-line `type_body_length`, move `stackDropTarget` and `stackChildren` into an `extension BoardDocumentContentView` in `moody/Views/BoardDocumentContentView+Stacks.swift`. `private` doesn't reach across files, so drop `private` from every member the extension reads: `stackChildren`, `stackDropTarget`, `movingItemIDs` and `activeDragItemID`.

- [ ] **Step 6: Manual QA (zoom 100% and 50%)**

1. Drag a photo over a "Geneva" column: the outline turns accent. Release: it snaps under the header.
2. Drop three more at different heights: each lands where released.
3. Drag the second photo below the last one: reordered. Click a stacked photo without moving it: no change (Review Focus 4).
4. Drag a stacked photo out onto empty canvas: it stays there and the stack closes up.
5. Drag the container: its photos move with it with no lag, and stay stacked after release.
6. Marquee three loose photos and drag them onto the container together: all three are added in on-screen order.
7. Select a container and a loose photo and Align Left: the container's photos move with it.
8. Delete a stacked photo (confirm): the stack closes up. Delete the container: its photos stay where they were.

---

### Task 10: Finder drop into a container

**Files:**
- Modify: `moody/Import/ImageImportService.swift` (`container:` on `importDroppedItems`, `importOne`, `insertImage`)
- Modify: `moody/Views/BoardDocumentContentView.swift` (`.onDrop` hit-test)
- Test: `moodyTests/ImageImportServiceTests.swift`

**Interfaces:**
- Consumes: `insertIntoStack` (Task 7), `topmostContaining` (Task 6).
- Produces: `ImageImportService.importDroppedItems(_:into:at:container:context:storage:)` and `insertImage(data:fileExtension:into:at:container:context:storage:)`, with `container: BoardItem? = nil` placed after `at:`.

- [ ] **Step 1: Write the failing test**

Add to `ImageImportServiceTests`:

```swift
    @Test func insertImageIntoAContainerAppendsItToTheStack() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("moody-tests-\(UUID().uuidString)", isDirectory: true)
        let storage = FileStorageService(rootDirectory: root)
        let container = try ModelContainer(
            for: Folder.self, Project.self, BoardItem.self, BoardConnector.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let project = Project(name: "Board")
        context.insert(project)
        let stack = BoardItem.container(axis: .column, at: CGPoint(x: 120, y: 80), zIndex: 1, project: project)
        context.insert(stack)

        for _ in 0 ..< 2 {
            try ImageImportService.insertImage(
                data: ImageFixtures.make(width: 200, height: 100, fill: ImageFixtures.red),
                fileExtension: "png",
                into: project,
                at: CGPoint(x: 5000, y: 5000),
                container: stack,
                context: context,
                storage: storage
            )
        }

        let photos = project.items.filter { $0.kind == .image }.sorted { $0.stackOrder < $1.stackOrder }
        #expect(photos.count == 2)
        #expect(photos.allSatisfy { $0.container?.id == stack.id })
        #expect(photos.map(\.stackOrder) == [0, 1])
        #expect(photos[0].positionX == stack.positionX)
        #expect(photos[0].positionY < photos[1].positionY)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/ImageImportServiceTests`
Expected: build FAILS with "extra argument 'container' in call".

- [ ] **Step 3: Thread `container` through `ImageImportService`**

`importDroppedItems`: add the parameter `container: BoardItem? = nil,` after `at dropLocation: CGPoint,` and pass `container: container` to `importOne`. `importOne`: add the parameter `container: BoardItem?,` after `at position: CGPoint,` and pass it to `insertImage`. `insertImage`: add `container: BoardItem? = nil,` after `at position: CGPoint,`. Between `context.insert(item)` and `try context.save()` add:

```swift
        if let container {
            insertIntoStack([item], container: container, at: Int.max, allZIndices: project.items.map(\.zIndex))
        }
```

Update its doc comment: `/// Writes the file to the board's storage and inserts its BoardItem on top, or at the end of container's stack. Shared by board drops and the Add Border tool.`

- [ ] **Step 4: Hit-test containers in `.onDrop`**

Replace the `.onDrop` closure body with:

```swift
            let dropPoint = logicalPoint(from: location)
            let containers = items.filter { $0.kind == .container }
            let targetID = topmostContaining(dropPoint, items: containers.map { (id: $0.id, center: $0.center, size: $0.size) })
            let target = containers.first { $0.id == targetID }
            Task {
                await ImageImportService.importDroppedItems(
                    providers, into: project, at: dropPoint, container: target, context: modelContext
                )
            }
            return true
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/ImageImportServiceTests`
Expected: PASS.

- [ ] **Step 6: Lint + manual QA**

Run: `swiftformat . && swiftlint lint --strict`, which should report no violations. Then in the app:
1. Drag three JPEGs plus one SVG from Finder onto a row container: all four are appended left to right.
2. Drop files onto empty canvas: they land loose and cascaded, as before.
3. Repeat at zoom 200%.

---

# Phase 3 — Connectors

### Task 11: Connector geometry and lookup

**Files:**
- Create: `moody/Views/Annotations/ConnectorGeometry.swift`
- Test: `moodyTests/ConnectorTests.swift`

**Interfaces:**
- Consumes: `BoardConnector`, `outgoingConnectors` / `incomingConnectors` (Task 1).
- Produces: `func connectorEndpoints(from: CGRect, to: CGRect) -> (start: CGPoint, end: CGPoint)?`; `func connector(between a: BoardItem, and b: BoardItem) -> BoardConnector?`.

- [ ] **Step 1: Write the failing test**

Create `moodyTests/ConnectorTests.swift`:

```swift
//
//  ConnectorTests.swift
//  moodyTests
//

import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import moody

struct ConnectorTests {
    private func isClose(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) < 0.001 && abs(lhs.y - rhs.y) < 0.001
    }

    // MARK: - connectorEndpoints

    @Test func horizontalNeighboursConnectFacingEdges() throws {
        let ends = try #require(connectorEndpoints(
            from: CGRect(x: 0, y: 0, width: 100, height: 100),
            to: CGRect(x: 200, y: 0, width: 100, height: 100)
        ))
        #expect(isClose(ends.start, CGPoint(x: 100, y: 50)))
        #expect(isClose(ends.end, CGPoint(x: 200, y: 50)))
    }

    @Test func verticalNeighboursConnectFacingEdges() throws {
        let ends = try #require(connectorEndpoints(
            from: CGRect(x: 0, y: 300, width: 100, height: 100),
            to: CGRect(x: 0, y: 0, width: 100, height: 50)
        ))
        #expect(isClose(ends.start, CGPoint(x: 50, y: 300)))
        #expect(isClose(ends.end, CGPoint(x: 50, y: 50)))
    }

    @Test func diagonalLineLeavesThroughTheCorners() throws {
        let ends = try #require(connectorEndpoints(
            from: CGRect(x: 0, y: 0, width: 100, height: 100),
            to: CGRect(x: 300, y: 300, width: 100, height: 100)
        ))
        #expect(isClose(ends.start, CGPoint(x: 100, y: 100)))
        #expect(isClose(ends.end, CGPoint(x: 300, y: 300)))
    }

    @Test func overlappingBoxesHaveNoLine() {
        #expect(connectorEndpoints(
            from: CGRect(x: 10, y: 10, width: 50, height: 50),
            to: CGRect(x: 0, y: 0, width: 240, height: 160)
        ) == nil)
    }

    // MARK: - connector(between:and:)

    @MainActor
    @Test func connectorLookupWorksInBothDirections() throws {
        let schema = Schema([Project.self, BoardItem.self, BoardConnector.self])
        let context = ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
        let project = Project(name: "Board")
        context.insert(project)
        let a = BoardItem.note(at: .zero, zIndex: 1, project: project)
        let b = BoardItem.note(at: CGPoint(x: 500, y: 0), zIndex: 2, project: project)
        let c = BoardItem.note(at: CGPoint(x: 0, y: 500), zIndex: 3, project: project)
        for note in [a, b, c] {
            context.insert(note)
        }
        let link = BoardConnector(from: a, to: b)
        context.insert(link)
        try context.save()

        #expect(connector(between: a, and: b)?.id == link.id)
        #expect(connector(between: b, and: a)?.id == link.id)
        #expect(connector(between: a, and: c) == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/ConnectorTests`
Expected: build FAILS with "cannot find 'connectorEndpoints' in scope".

- [ ] **Step 3: Create `moody/Views/Annotations/ConnectorGeometry.swift`**

```swift
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

/// The connector linking `a` and `b`, in either direction.
func connector(between a: BoardItem, and b: BoardItem) -> BoardConnector? {
    (a.outgoingConnectors + a.incomingConnectors).first { $0.from?.id == b.id || $0.to?.id == b.id }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/ConnectorTests`
Expected: PASS.

- [ ] **Step 5: Lint**

Run: `swiftformat . && swiftlint lint --strict`
Expected: no violations.

---

### Task 12: Draw, select, connect and unlink lines

**Files:**
- Create: `moody/Views/Annotations/ConnectorLayerView.swift`
- Modify: `moody/Views/BoardView.swift` (`selectedConnectorID`, `connectors`, Connect/Unlink toolbar, delete key)
- Modify: `moody/Views/BoardCanvasView.swift` (`connectors`, `selectedConnectorID` passthrough)
- Modify: `moody/Views/BoardDocumentContentView.swift` (layer, live rects, selection exclusivity)

**Interfaces:**
- Consumes: `connectorEndpoints`, `connector(between:and:)` (Task 11); `movingItemIDs` / `dragTranslation` (Task 9).
- Produces: `ConnectorLayerView(connectors:extentOrigin:isDarkBoard:selectedConnectorID:liveRect:onSelect:onUnlink:)`. `BoardCanvasView` properties in order: `project, items, connectors, zoomScale, zoomAnchor, selectedItemIDs, editingItemID, selectedConnectorID, controller, onDeleteKey`. `BoardDocumentContentView` properties in order: `project, items, connectors, extent, zoomScale, zoomAnchor, selectedItemIDs, editingItemID, selectedConnectorID`.

- [ ] **Step 1: Create `moody/Views/Annotations/ConnectorLayerView.swift`**

```swift
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
```

- [ ] **Step 2: Plumb connectors and connector selection**

`BoardView`:

```swift
    /// The clicked connector line. Ephemeral, and never set together with selectedItemIDs.
    @State private var selectedConnectorID: UUID?

    /// Every connector starts at one of this board's items.
    private var connectors: [BoardConnector] {
        items.flatMap(\.outgoingConnectors)
    }
```

In the `BoardCanvasView(...)` call, pass `connectors: connectors` after `items:` and `selectedConnectorID: $selectedConnectorID` after `editingItemID:`.

`BoardCanvasView`: add `let connectors: [BoardConnector]` after `items` and `@Binding var selectedConnectorID: UUID?` after `editingItemID`. In `makeContent()`, pass `connectors: parent.connectors` after `items:` and `selectedConnectorID: parent.$selectedConnectorID` after `editingItemID:`.

`BoardDocumentContentView`: add `let connectors: [BoardConnector]` after `items` and `@Binding var selectedConnectorID: UUID?` after `editingItemID`.

- [ ] **Step 3: Render the layer in `BoardDocumentContentView`**

In the `ZStack`, right after `BoardBackgroundView(…).gesture(marqueeGesture)` and the `let moving = movingItemIDs` line:

```swift
            ConnectorLayerView(
                connectors: connectors,
                extentOrigin: extent.origin,
                isDarkBoard: project.usesDarkBackground,
                selectedConnectorID: selectedConnectorID,
                liveRect: { liveRect(of: $0, moving: moving) },
                onSelect: { id in
                    endEditing()
                    selectedItemIDs = []
                    selectedConnectorID = id
                },
                onUnlink: unlink
            )
            // Above the background (0), below every item (zIndex ≥ 1 via nextZIndex).
            .zIndex(0.5)
```

Add:

```swift
    private func liveRect(of item: BoardItem, moving: Set<UUID>) -> CGRect {
        let offset = moving.contains(item.id) ? dragTranslation : .zero
        return CGRect(
            x: item.positionX - item.width / 2 + offset.width,
            y: item.positionY - item.height / 2 + offset.height,
            width: item.width,
            height: item.height
        )
    }

    /// Context-menu click, never mid-gesture.
    private func unlink(_ connector: BoardConnector) {
        if selectedConnectorID == connector.id {
            selectedConnectorID = nil
        }
        modelContext.delete(connector)
        try? modelContext.save()
    }
```

Selecting items clears the line: in `handleItemDragChanged` inside `if activeDragItemID == nil {` add `selectedConnectorID = nil`. In `marqueeGesture`'s `.onChanged` add `selectedConnectorID = nil`.

- [ ] **Step 4: Toolbar Connect / Unlink and ⌫ in `BoardView`**

Add:

```swift
    /// The link between exactly two selected items, if they're linked.
    private var selectedPairConnector: BoardConnector? {
        guard selectedItems.count == 2 else { return nil }
        return connector(between: selectedItems[0], and: selectedItems[1])
    }

    /// Toolbar click, never mid-gesture.
    private func toggleConnection() {
        guard selectedItems.count == 2 else { return }
        if let existing = selectedPairConnector {
            modelContext.delete(existing)
        } else {
            modelContext.insert(BoardConnector(from: selectedItems[0], to: selectedItems[1]))
        }
        try? modelContext.save()
    }

    private func unlinkSelectedConnector() {
        guard let id = selectedConnectorID, let selected = connectors.first(where: { $0.id == id }) else { return }
        selectedConnectorID = nil
        modelContext.delete(selected)
        try? modelContext.save()
    }
```

Change `handleDeleteKey()` to start with:

```swift
        if selectedConnectorID != nil {
            unlinkSelectedConnector()
            return true
        }
```

Restructure the toolbar's `if selectedItems.isEmpty { … } else { … }` into three branches:

```swift
            if !selectedItems.isEmpty {
                // existing selection items (alignment, Download Selected, Delete), plus:
                ToolbarItem(placement: .primaryAction) {
                    Button(
                        selectedPairConnector == nil ? "Connect" : "Unlink",
                        systemImage: selectedPairConnector == nil ? "link" : "scissors",
                        action: toggleConnection
                    )
                    .help(selectedPairConnector == nil ? "Connect the Two Selected Items" : "Unlink the Two Selected Items")
                    .disabled(selectedItems.count != 2)
                }
            } else if selectedConnectorID != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Unlink", systemImage: "scissors", action: unlinkSelectedConnector)
                        .help("Unlink (⌫)")
                }
            } else {
                // existing default group (Grid, Background, Download All)
            }
```

Keep the existing contents of the first and last branches unchanged. Place the Connect item before the Delete item.

- [ ] **Step 5: Build, tests, lint**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' && swiftformat . && swiftlint lint --strict`
Expected: PASS, no violations.

- [ ] **Step 6: Manual QA (zoom 100% and 200%)**

1. Select a note and a photo, then click Connect: a gray line joins their facing edges.
2. Drag the photo: the line follows live. Drag the container holding a connected photo: the line follows.
3. Click the line: it turns accent and the toolbar shows Unlink. Press ⌫: it's gone.
4. Reconnect them, then right-click the line ▸ Unlink.
5. Select the same two items: the button reads Unlink and removes the line.
6. Connect a photo to its own container: no line is drawn and nothing crashes (Review Focus 5). Drag the photo out: the line appears.
7. Delete a connected note: its line disappears.
8. On a dark board, lines are light gray.

---

### Task 13: Documentation and full verification

**Files:**
- Modify: `CLAUDE.md` (Architecture)

- [ ] **Step 1: Update `CLAUDE.md`**

In **Data model**, after the `BoardItem` sentence, add: `A BoardItem's kindRaw (read via kind: .image / .note / .container, unknown → .image) makes it a photo, a sticky note (text, colorName) or a row/column container (title, iconName, colorName, axis); fileName is "" for non-photos. Stacked photos point at their container (container / stackedItems, nullify — deleting a container leaves its photos loose) with a stackOrder. BoardConnector links two items (from / to); BoardItem's outgoingConnectors / incomingConnectors cascade, so deleting either end removes the line.`

Add a paragraph after **Canvas view stack**:

`**Annotations** (moody/Views/Annotations/). The toolbar Add menu creates notes and containers at BoardCanvasController.visibleCenter. Double-click to edit is read from NSApp.currentEvent?.clickCount in handleItemDragEnded, not from a TapGesture. Editing writes the model live and saves in endEditing(). Stack layout is pure (ContainerLayout.swift). Membership changes (insertIntoStack, removeFromStack, commitStackDrop, relayout in ContainerStacking.swift) run only on drag end, menu actions or import, and keep the container's top-left fixed. Dragging a container moves its stack via expandingContainers. Connector lines (ConnectorLayerView, zIndex 0.5) use live rects, so they follow drags without model writes. Delete (toolbar or ⌫, through a key monitor in BoardCanvasView's coordinator that skips NSText first responders) goes through deleteBoardItems, which also removes photo files and asks first when photos are involved.`

- [ ] **Step 2: Full verification**

Run:

```sh
swiftformat --lint .
swiftlint lint --strict
xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS'
```

Expected: no lint violations; all unit and UI tests PASS.

- [ ] **Step 3: Regression pass on an existing board**

Open a board created before this branch: every photo is present and draggable. Zoom to Fit, Grid, Background, Download All and Add Border still work.
