# Photo Count Badge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the board's photo count next to the zoom percentage in the bottom-right badge, e.g. `24 photos · 100%`.

**Architecture:** One edit to the existing `.overlay(alignment: .bottomTrailing)` in `BoardView`. The count is derived from the `items` `@Query` the view already owns, so it updates on drop, delete and undo with no extra state. Pluralization uses SwiftUI automatic grammar agreement (`^[…](inflect: true)`).

**Tech Stack:** SwiftUI, SwiftData (`@Query`), Swift 6 `Sequence.count(where:)`.

**Spec:** No spec file. This is a bounded change; the design was agreed in chat:
- Count photos only (`kind == .image`); notes and containers are not counted.
- Always show the board total, independent of selection (option A).
- Show `0 photos` on an empty board rather than hiding the count.
- Same capsule styling as today; only `moody/Views/BoardView.swift` changes.

## Global Constraints

- macOS 27, Xcode 27; `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (nothing new is off-main).
- `swiftformat --lint .` and `swiftlint lint --strict` must pass (4-space indent, 140-col lines).
- Do not touch the zoom invariants: the badge stays `.allowsHitTesting(false)` so it never steals canvas clicks or drops.
- No git commits: the user commits their own work.

## Review Focus

1. **Notes and containers on the board:** a board with 2 photos, 1 note and 1 container reads `2 photos`, not `4`. Checked manually in Task 1, Step 4.
2. **Singular:** a board with exactly 1 photo reads `1 photo`, not `1 photos`. Checked manually in Task 1, Step 4.
3. **Empty board:** a new board reads `0 photos · 100%` and the badge doesn't collapse or jump. Checked manually in Task 1, Step 4.
4. **Live updates:** dropping an image or deleting a photo (⌫) changes the count right away, without switching boards. Checked manually in Task 1, Step 4.
5. **Stacked photos:** photos inside a row/column container are still `.image` items and are counted. Checked manually in Task 1, Step 4.

None of these gets an automated test. The logic is one filter over a `@Query` inside a view, and this repo's UI tests can't reliably read overlay text (see the sidebar UI test note in `CLAUDE.md`). Extracting a helper only to test `count(where:)` would add code without catching anything real.

---

### Task 1: Photo count in the zoom badge

**Files:**
- Modify: `moody/Views/BoardView.swift:88-97` (the `.overlay(alignment: .bottomTrailing)` block)

**Interfaces:**
- Consumes: `items: [BoardItem]` (existing `@Query` in `BoardView`), `BoardItem.kind` / `BoardItemKind.image`, `zoomScale` (existing `@State`).
- Produces: nothing other code depends on.

- [ ] **Step 1: Add the computed count**

In `BoardView`, next to the existing `selectedImages` computed property, add:

```swift
    private var photoCount: Int {
        items.count { $0.kind == .image }
    }
```

- [ ] **Step 2: Replace the badge text**

Replace the current overlay block:

```swift
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
```

with:

```swift
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 4) {
                Text("^[\(photoCount) photo](inflect: true)")
                Text("·")
                    .foregroundStyle(.secondary)
                Text(zoomScale, format: .percent.precision(.fractionLength(0)))
            }
            .font(.caption)
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .padding(12)
            .allowsHitTesting(false)
        }
```

Keep the string literal passed straight to `Text`, so it becomes a `LocalizedStringKey`. The inflection markdown only works that way; a `String` variable would render the brackets literally.

- [ ] **Step 3: Build and lint**

Run:

```sh
xcodebuild build -project moody.xcodeproj -scheme moody -destination 'platform=macOS'
swiftformat --lint .
swiftlint lint --strict
```

Expected: `** BUILD SUCCEEDED **`, and both linters report 0 violations.

- [ ] **Step 4: Verify in the running app**

Launch the app (Xcode ▸ Run, or the `run` skill), then:

1. Create a new board. The badge reads `0 photos · 100%`.
2. Drop one image. It reads `1 photo · 100%`.
3. Drop a second image, then add a Note and a Row Container from the toolbar's Add menu. It reads `2 photos`.
4. Stack one photo into the container (right-click ▸ New Row Container, or drag it in). It still reads `2 photos`.
5. Select a photo and press ⌫ (confirm the dialog). It reads `1 photo`.
6. Pinch or ⌘0 to zoom. The percentage changes and the count stays put; the badge doesn't block clicks or drops beneath it.

- [ ] **Step 5: Run the existing test suite**

Run:

```sh
xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS'
```

Expected: `** TEST SUCCEEDED **` (no regressions; no tests reference the badge).
