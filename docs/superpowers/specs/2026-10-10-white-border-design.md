# Border tool — design

## Goal

A tool that adds a clean border to several images at once. The border is white by default, for a print / gallery look. The results go either onto a board or straight into a folder on disk, without touching any board. Output keeps the source's aspect ratio, native resolution and quality. The border is rendered at the same pixel resolution as the image.

## Decisions

| Topic | Decision |
|---|---|
| Source | Image files, picked with **Choose Images…** (`NSOpenPanel`, multiple) or **dragged onto the tool** from Finder or other apps. Board items are not a source. |
| Border size | Uniform on all 4 sides: `round(percent × long edge)` px. 5% of 4000×3000 → 200 px on every side. Range 0–50%, default 5%. |
| Border color | A color picker without opacity, defaulting to white. |
| Destination | Either a board (a picker over all boards, defaulting to the open board) or a user-chosen folder. |
| Entry point | **Tools ▸ Add Border…** (⇧⌘B), opening a sheet on the active window. It's not called "White Border" because the color can be changed. |
| Quality | Native pixel size, source color space and bit depth, same file format. Lossy formats are re-encoded once at maximum quality. |

## Design

### 1. Renderer — `moody/Import/BorderRenderer.swift`

`nonisolated`, so it runs off the main actor (like `FileStorageService`).

- `borderWidth(pixelWidth:pixelHeight:percent:) -> Int` = `Int((Double(max(w, h)) * percent / 100).rounded())`.
- `addBorder(to data: Data, percent: Double, color: CGColor) throws -> BorderedImage` (data, output `contentType`, pixel size). The format is read from the data itself (`CGImageSourceGetType`):
  1. `CGImageSourceCreateWithData` → `CGImage` at index 0, plus its properties (EXIF, ICC, DPI, orientation).
  2. A `CGContext` of size `(w + 2b) × (h + 2b)` that uses the **source's color space, bits per component and alpha info**: 16-bit stays 16-bit, Display P3 stays P3, grayscale stays gray. It falls back to sRGB at the same bit depth in two cases:
     - the source format can't back a bitmap context (e.g. indexed PNG);
     - the source is grayscale and the border color isn't neutral. Without this, a red border would come out gray.
  3. Fill the canvas with `color.converted(to: contextSpace, intent: .defaultIntent, options: nil)`. Then draw the image at the integer offset `(b, b)`, at its exact pixel size, with the `.copy` blend mode. There's no resampling, and the original pixels, transparency included, are bit-identical.
  4. Encode with `CGImageDestination` in the **same UTType**, copying the source properties. JPEG and HEIC use `kCGImageDestinationLossyCompressionQuality = 1.0`; PNG and TIFF are lossless. Types ImageIO can't write (e.g. WebP) are encoded as PNG.
- EXIF orientation is kept unchanged. The border is uniform, so the result is correct in any orientation.
- SVG input is first rasterized with the existing `SVGRasterizer.rasterize`, then bordered as a PNG.

### 2. Loading sources

The picker and drag-and-drop share one path. The tool's list holds `(name, data, contentType)`, read when the image is added, so rendering never depends on a sandbox-scoped URL staying readable.

- **Drop:** `.onDrop(of: [.image], isTargeted:)` on the sheet, with a highlight while hovering. Each `NSItemProvider` is read with `ImageImportService.loadFileRepresentation`, which changes from `private` to internal. The name comes from `provider.suggestedName`. This handles Finder files and images dragged from Safari or Photos alike. Items that aren't images, or can't be read, are skipped and counted.
- **Choose Images…:** `NSOpenPanel` (`allowedContentTypes: [.image]`, multiple) → `Data(contentsOf:)` plus the URL's `contentType` resource value, with the same fallback chain as `loadFileRepresentation`.

### 3. Board output

The tail of `ImageImportService.importOne` (write data → insert `BoardItem`) is extracted into a shared `insertImage(data:fileExtension:pixelWidth:pixelHeight:into:at:context:storage:)`. The board drop path and the tool both use it.

Bordered images are placed to the right of the board's existing content. The pure helper `appendedImportCenter(contentBounds:size:)` in `ImportGeometry.swift` gives the center: recomputed after each insert, so a batch lands in a row; an empty board starts at the origin. It builds on `boardContentBounds` (`CanvasExtent.swift`).

### 4. Folder output

An `NSOpenPanel` set to directories, with `canCreateDirectories` and the prompt "Save", as in `BoardView.download`. Files are named `<original name> border.<ext>`. When that name is taken, the next free `… border 2.<ext>`, `… border 3.<ext>`, and so on is used. User files are never overwritten. The names come from the pure helper `uniqueBorderFileName(base:fileExtension:taken:)` (in `BorderToolService.swift`). The sandbox already has `ENABLE_USER_SELECTED_FILES = readwrite`.

### 5. UI — `moody/Views/Border/BorderToolView.swift`

A sheet presented by `RootView`:

- **Drop zone / file list** reading "Drop images here or Choose Images…", with a remove button per file.
- **Border %**: a 0–50 slider plus a numeric field.
- **Border color**: `ColorPicker(supportsOpacity: false)`, default `.white`, passed to the renderer as a `CGColor`.
- A small live preview of the first image: a SwiftUI `Image` with proportional padding in the chosen color, for display only.
- **Destination**: segmented Board / Folder. Board shows a `Picker` over the `@Query` projects.
- **Apply** renders in a detached task, one file at a time. As with import, one failure doesn't abort the batch. A `ProgressView` shows while it works. Models are then inserted on main, or files written. Failures are counted in an alert, like `BoardView`'s download failure. The sheet closes on success.

Command wiring: `moodyApp` adds `.commands { CommandMenu("Tools") { … } }`. The button toggles a `@FocusedBinding` that `RootView` publishes with `.focusedSceneValue`, so the sheet opens in the active window. `RootView` passes its current `.board(id)` selection as the default target.

## Testing

Swift Testing in `moodyTests/BorderRendererTests.swift`. Source images are generated in memory with `CGContext`.

- `borderWidth`: landscape, portrait, square, 0%, rounding.
- Output size is `(w + 2b) × (h + 2b)`. Corner and edge-band pixels equal the border color, checked with white and with a non-white color. An interior pixel equals the source pixel.
- PNG in → PNG out and JPEG in → JPEG out. A 16-bit PNG keeps 16 bits per component, and the color space name is preserved.
- A grayscale source with a white border stays grayscale. A grayscale source with a red border comes out as RGB with a red border.
- A transparent source pixel stays transparent.
- `appendedImportCenter` cases in `ImportGeometryTests`; `uniqueBorderFileName` cases in `BorderToolServiceTests`.

Manual QA:
1. Press ⇧⌘B. Drag a JPEG, a PNG and an SVG from Finder, and one image from Safari, onto the sheet.
2. Pick a color and send the images to a board at 5%. They appear right of the existing content.
3. Do the same to a folder. The files open in Preview with the correct size, colors and EXIF.
4. Repeat the folder export to check that nothing is overwritten.

## Out of scope

Border opacity, remembering the last color between launches, dragging results out of the tool, per-side widths, and board items as a source.
