# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

moody is a macOS-only moodboard app (SwiftUI + AppKit + SwiftData, deployment target macOS 27, Xcode 27). Users create boards in a sidebar and drag images (including SVGs) onto an infinite-feeling zoomable canvas.

Build settings worth knowing: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` — types are main-actor by default, so pure/off-main types must be marked `nonisolated` (see `FileStorageService`). The project uses Xcode file-system-synchronized groups: new `.swift` files dropped into `moody/`, `moodyTests/`, or `moodyUITests/` are picked up automatically without editing `project.pbxproj`.

## Commands

Lint (CI runs both and fails on any violation):

```sh
swiftformat --lint .      # check; drop --lint to auto-fix
swiftlint lint --strict
```

Build / test (scheme `moody`, project `moody.xcodeproj`):

```sh
xcodebuild build -project moody.xcodeproj -scheme moody -destination 'platform=macOS'
xcodebuild test  -project moody.xcodeproj -scheme moody -destination 'platform=macOS'

# Single suite or single test (Swift Testing: Target/Suite/testFunction())
xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' \
  -only-testing:moodyTests/FileStorageServiceTests
xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' \
  -only-testing:'moodyTests/FileStorageServiceTests/deletingAFileRemovesOnlyThatFile()'
```

UI tests launch the app with `-inMemoryStore` (checked in `moodyApp.swift`) so they never touch the real library. In sidebar UI tests the row text isn't reliably queryable; `SidebarRenameUITests` asserts via the window title (the detail's `navigationTitle`).

CI (`.github/workflows/ci.yml`) also passes ad-hoc signing overrides (`CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=`), builds Release, and packages a DMG with `create-dmg`. Pushing a `v*.*.*` tag publishes a GitHub Release.

Style limits enforced by `.swiftformat` / `.swiftlint.yml`: 4-space indent, 140-col lines, trailing commas mandatory in multi-line collections, `self.` removed where not required, `@testable import` grouped last.

## Architecture

**Data model (SwiftData).** `Project` has many `BoardItem`s with a cascade delete rule. A `BoardItem` stores a bare `fileName` (never a path), a center position in board document coordinates (`positionX/Y`, matching SwiftUI `.position`), a fixed display size, natural pixel size, and an explicit `zIndex` used as the `@Query` sort key. Boards are organized in a tree of `Folder`s: `Folder.parent` (nil = top level) with cascade-deleted `subfolders` and `projects`; `Project.folder` (nil = top level). A folder stores its SF Symbol `iconName` and `colorName` as plain strings — always read them through `resolvedIconName` / `resolvedColor` (`FolderAppearance.swift`), which fall back to defaults for unknown values. New schema types must be added to the `Schema` in `moodyApp.swift` and to test containers.

**Image files live outside SwiftData.** `FileStorageService` maps files to `~/Library/Application Support/Moody/Projects/<project-id>/images/<fileName>`. Cascade delete only removes DB rows, so deleting a project must also call `deleteProjectDirectory` (done in `SidebarView.commitDelete`). Deleting a folder cascades through every nested board, so it must first collect `descendantProjects(of:)` and delete each of their directories. Tests inject a temp `rootDirectory`. `ImageCache` (NSCache keyed by fileName) avoids re-decoding images on every re-render.

**Import pipeline** (`moody/Import/`). `ImageImportService.importDroppedItems` processes each dropped `NSItemProvider` independently (one failure doesn't abort the batch): read bytes inside the provider's completion handler (the temp URL is only valid there), rasterize SVGs to PNG via an offscreen `WKWebView` (`SVGRasterizer`, sized by `SVGIntrinsicSizeParser`; manual QA only, not unit tested), decode pixel size, write to storage, insert the model. Pure geometry helpers (`aspectFit`, `cascadePosition`, `nextZIndex`) live in `ImportGeometry.swift` and are reused by the board.

**Sidebar** (`moody/Views/Sidebar/`). `SidebarView` owns the `@Query`s, selection (`SidebarSelection`: `.folder(UUID)` / `.board(UUID)`, resolved to models in `RootView`), and the rename / appearance-popover / delete state; `SidebarFolderRow` (recursive `DisclosureGroup`, expansion persisted in `Folder.isExpanded`) and `SidebarBoardRow` receive it through `SidebarRowActions`. Double-click (and Return) rename goes through `contextMenu(forSelectionType:primaryAction:)` — don't replace it with a `TapGesture(count: 2)` on the row, which breaks single-click selection in a macOS `List`. `InlineRenameField` re-requests focus until it lands (`claimFocus`): after a double-click the outline view still owns first responder and drops a one-shot `@FocusState` request. Create actions live in a single toolbar "New" menu — separate buttons overflow the narrow sidebar toolbar. Rows drag a `SidebarItemReference` whose custom UTType is declared under `UTExportedTypeDeclarations` in `moody/Info.plist` (merged with the generated plist; edit it via Xcode, keeping the identifier in sync with `UTType.moodySidebarItem`). Tree logic (ordering, `canMove` cycle check, `move`, `uniqueName`, `folderOutline`) lives in `SidebarTree.swift`.

**Canvas view stack.** `RootView` (NavigationSplitView) → `BoardView` (owns `@Query` filtered by project, sorted by `zIndex`, plus zoom state) → `BoardCanvasView` (`NSViewRepresentable` wrapping a plain `NSScrollView` whose documentView is an `NSHostingView` sized to a content-aware `extent`) → `BoardDocumentContentView` → `BoardItemView`. The extent is the photos' bounds ± half a viewport, unioned with the visible rect (see `CanvasExtent.swift`); board coordinates are unbounded and the content view renders them shifted by `−extent.origin`. The extent never shrinks during a live scroll, only when it ends. `BoardView`'s toolbar has Zoom to Fit (⌘0), which goes through `BoardCanvasController`, since only the canvas coordinator knows the viewport.

Two invariants are load-bearing; the file headers explain them in detail and they must be preserved:

1. **Zoom is done in SwiftUI (`.scaleEffect` + magnification gesture), never `NSScrollView.allowsMagnification`.** AppKit magnification breaks SwiftUI hit-testing (hover, drag, drop) at any zoom ≠ 1. `BoardCanvasView` resizes the hosting frame to `extent.size * zoomScale` and adjusts the scroll offset to keep zoom anchored at the cursor. Gestures attached outside the `.scaleEffect` get post-scale points and need `logicalPoint(from:)`; gestures attached inside get extent-local coordinates (board minus `extent.origin`) — add the origin, but don't run them through `logicalPoint(from:)` too.
2. **No `@Model` writes mid-gesture.** Position and `zIndex` changes are committed only in `.onEnded` (via `commitGroupMove` in `BoardGroupMove.swift`, followed by `modelContext.save()`). Writing `zIndex` during `.onChanged` re-sorts the `@Query`, can reassign the hosting view's rootView, and silently kills the in-flight drag. Live drag/selection state (`selectedItemIDs`, `dragTranslation`, `activeDragItemID`, `marqueeRect`) is plain `@State` in `BoardDocumentContentView`, not on individual items and never persisted.

Testable logic is pulled out of views into free functions/small types (`BoardGroupMove`, `BoardSelectionGeometry`, `CanvasExtent`, `ImportGeometry`, `SidebarTree`) and covered by Swift Testing (`@Test`, `#expect`) in `moodyTests/`; SwiftData tests use an in-memory `ModelContainer`.

## Plans

Implementation plans are written to `docs/superpowers/plans/` (e.g. the board multi-select and sidebar folders plans), and they record design rationale beyond what the code comments cover.
