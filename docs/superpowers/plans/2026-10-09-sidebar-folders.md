# Sidebar Folders (tree, icon/color, inline rename) — Implementation Plan

## Context

The sidebar (`moody/Views/ProjectListView.swift`) is a flat `List` of boards sorted by `createdAt`, with rename via an alert and delete via a confirmation dialog. As the number of moodboards grows there is no way to organize them. Goal: a richer, Finder/Notes-style sidebar where boards can be grouped in nested folders, folders have a user-chosen SF Symbol icon and color, and both folders and boards can be renamed inline by double-clicking.

Path classification: **architectural** (new SwiftData entity + sidebar restructure). This plan doubles as the design spec; on approval it is first copied to `docs/superpowers/plans/2026-10-09-sidebar-folders.md` (per CLAUDE.md). No git commits — the user commits their own work.

### Decisions (confirmed with user)
- **Unlimited nesting**: folders contain folders and boards to any depth.
- **Moving**: drag & drop in the sidebar **and** a "Move to ▸" context-menu submenu.
- **Deleting a folder deletes everything inside** (subfolders, boards, image files), after a confirmation that states the board count.
- **Appearance**: curated popover — grid of ~30 SF Symbols + 12 preset colors.

### Additional design choices (mine, YAGNI-trimmed)
- Ordering: folders first, then boards; each sorted by name with `localizedStandardCompare` (Finder-like). No manual reordering.
- Expanded/collapsed state persisted on the folder (`isExpanded`) — sidebar isn't the canvas, so writing on toggle is safe.
- New folder / new board is created inside the "current folder" (selected folder, or the parent folder of the selected board) and immediately enters inline-rename mode, like Finder.
- Double-click uses Apple's `contextMenu(forSelectionType:menu:primaryAction:)` — on macOS `primaryAction` fires on double-click (and Return) without breaking single-click selection, which a `TapGesture(count: 2)` on a List row would.
- Board rows show an item-count badge (`.badge`).

## Data model

New `moody/Models/Folder.swift`:
```swift
@Model final class Folder {
    var id: UUID
    var name: String
    var iconName: String        // SF Symbol name; unknown → default "folder"
    var colorName: String       // FolderColor raw value; unknown → .blue
    var isExpanded: Bool
    var createdAt: Date
    var parent: Folder?
    @Relationship(deleteRule: .cascade, inverse: \Folder.parent) var subfolders: [Folder] = []
    @Relationship(deleteRule: .cascade, inverse: \Project.folder) var projects: [Project] = []
}
```
`Project` gains `var folder: Folder?` (nil = top level). Adding an optional property and a new entity is a SwiftData lightweight migration — existing stores open unchanged, all boards land at top level.

Register `Folder.self` in the schema in `moody/moodyApp.swift`, the `RootView` preview, and existing test containers (`moodyTests/ProjectCascadeDeleteTests.swift`).

**Image-file invariant:** cascade delete only removes rows, so folder deletion must first collect every descendant project ID and call `FileStorageService().deleteProjectDirectory(projectID:)` for each (same pattern as today's `ProjectListView.commitDelete`).

## New files (all auto-picked up by file-system-synchronized groups)

Pure / testable (in `moody/Views/Sidebar/`):
- `FolderAppearance.swift` — `enum FolderColor: String, CaseIterable` (red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, brown, gray) with `var color: Color`; `enum FolderIcon { static let all: [String] }` curated SF Symbols (folder, star, heart, paintpalette, camera, photo, house, leaf, flame, bolt, sparkles, tshirt, car, airplane, book, music.note, film, cup.and.saucer, fork.knife, pawprint, globe, briefcase, gift, lightbulb, moon, sun.max, cloud, drop, building.2, person.2…); `Folder` extension `resolvedColor` / `resolvedIconName` with fallbacks.
- `SidebarTree.swift` — free functions, no SwiftUI:
  - `sortedChildren(folders:projects:)` → folders-then-boards ordering.
  - `descendantProjects(of folder: Folder) -> [Project]` (recursive).
  - `canMove(_ folder: Folder, into target: Folder?) -> Bool` (rejects self and descendants).
  - `move(_ item: SidebarItemReference, into target: Folder?, folders:projects:)` — resolves IDs, validates, reparents.
  - `uniqueName(_ base: String, among: [String])` → "Untitled Folder 2" etc.
- `SidebarSelection.swift` — `enum SidebarSelection: Hashable { case folder(UUID), board(UUID) }`.
- `SidebarItemReference.swift` — `Codable, Transferable` drag payload (`kind` + `id`) using `CodableRepresentation(contentType: .moodySidebarItem)`; `UTType(exportedAs: "gaelgothuey.moodyboard.sidebar-item", conformingTo: .data)`. Declare the type under `UTExportedTypeDeclarations` via an Info.plist addition (Xcode MCP `AddInfoPlist`; target uses `GENERATE_INFOPLIST_FILE`, which merges).

Views (in `moody/Views/Sidebar/`):
- `SidebarView.swift` — replaces `ProjectListView` (delete that file). `@Query` all folders and projects; renders top-level `SidebarFolderRow`s + `SidebarBoardRow`s in `List(selection: $selection)` with `.listStyle(.sidebar)`. Owns: `renamingTarget: SidebarSelection?`, `appearanceTarget: UUID?`, `pendingDelete: SidebarSelection?`. Toolbar `Menu` "+" → New Board (⌘N) / New Folder (⇧⌘N). `.contextMenu(forSelectionType: SidebarSelection.self, menu: …, primaryAction: { beginRename })`. Context menu: Rename, Change Icon & Color… (folders), New Board/Folder Here (folders), Move to ▸ (Top Level + nested folder list, invalid targets disabled), Delete. Delete confirmation reuses the existing `confirmationDialog` style; folder message: "This permanently deletes N boards and all their images." Also a `dropDestination` on empty list area → move to top level.
- `SidebarFolderRow.swift` — recursive: `DisclosureGroup(isExpanded: $folder.isExpanded) { children } label: { row }`; label = `Label { InlineRenameField or Text } icon: { Image(systemName: resolvedIconName).foregroundStyle(resolvedColor) }`, `.tag(.folder(id))`, `.draggable(SidebarItemReference)`, `.dropDestination(for: SidebarItemReference.self)` with `isTargeted` highlight → move into this folder; `.popover` for appearance.
- `SidebarBoardRow.swift` — `Label(name, systemImage: "photo.on.rectangle.angled")`, badge with `items.count`, `.tag(.board(id))`, draggable; drop on a board row moves into that board's parent folder.
- `InlineRenameField.swift` — `TextField` + `@FocusState` focused on appear, text selected; `onSubmit` commits (trimmed, non-empty, then `modelContext.save()`), Esc (`.onExitCommand`) cancels, focus loss commits.
- `FolderAppearancePicker.swift` — popover: `LazyVGrid` of icon buttons (selected one highlighted in folder color) + row of color swatches; writes `iconName`/`colorName` and saves immediately; accessibility labels on every button.

## Modified files
- `moody/Models/Project.swift` — add `folder` property.
- `moody/moodyApp.swift` — schema adds `Folder.self`.
- `moody/Views/RootView.swift` — selection becomes `SidebarSelection?`; resolve the selected board via `@Query` of projects; folder selection shows a `ContentUnavailableView` with the folder's icon/color, name and board count. Sidebar column width `min: 200, ideal: 240`.
- `moody/Views/ProjectListView.swift` — removed (logic migrates to `SidebarView`; `commitDelete` pattern reused).
- `CLAUDE.md` — Architecture: add `Folder` to the data-model paragraph (tree via `parent`/`subfolders`, cascade to projects, file-cleanup rule for folder delete via `descendantProjects`), a short "Sidebar" paragraph (SidebarView → SidebarFolderRow (recursive) / SidebarBoardRow; double-click rename via `contextMenu(forSelectionType:primaryAction:)` — don't replace with tap gestures; drag payload `SidebarItemReference` + declared UTType), and mention the new tests.

## Tests (Swift Testing, in-memory `ModelContainer`, TDD — tests first)
- `moodyTests/SidebarTreeTests.swift` — ordering (folders first, natural name sort), `descendantProjects` across 3 levels, `canMove` rejects self/descendant and accepts sibling/top-level, `move` reparents board and folder, `uniqueName`.
- `moodyTests/FolderCascadeDeleteTests.swift` — deleting a folder cascades subfolders, projects and their `BoardItem`s; deleting a board inside a folder leaves the folder.
- `moodyTests/FolderAppearanceTests.swift` — unknown `colorName`/`iconName` fall back to defaults; every `FolderIcon.all` entry resolves to a real SF Symbol (`NSImage(systemSymbolName:accessibilityDescription:) != nil`).
- Update `ProjectCascadeDeleteTests` schema to include `Folder`.

## Execution order
1. Copy plan to `docs/superpowers/plans/`.
2. Model: `Folder` + `Project.folder` + schema registrations; cascade tests.
3. `FolderAppearance` + tests.
4. `SidebarTree`, `SidebarSelection`, `SidebarItemReference` (+ Info.plist UTType) + tests.
5. Views: `InlineRenameField`, `FolderAppearancePicker`, rows, `SidebarView`; wire `RootView`; delete `ProjectListView`.
6. CLAUDE.md update.
7. Verification.

## Verification
- `swiftformat --lint .` and `swiftlint lint --strict` clean.
- Build + tests via Xcode MCP (`BuildProject`, `RunAllTests`) and/or `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS'`.
- `RenderPreview` of `SidebarView` and `FolderAppearancePicker` with in-memory sample tree.
- Manual run (`RunProject`): existing store opens with boards at top level; create nested folders; change icon/color; double-click a folder and a board → inline edit, Return commits, Esc cancels; drag board into folder, folder into folder, folder onto its own child (rejected), board back to top level; "Move to" menu; delete a folder with boards → confirm count, rows gone, `~/Library/Application Support/Moody/Projects/<id>` directories removed; collapse state survives relaunch; board canvas drag/zoom unaffected.
