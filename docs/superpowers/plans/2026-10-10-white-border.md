# Add Border Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** **Tools ▸ Add Border…** (⇧⌘B) opens a sheet. Users drop or choose image files there, set a border percentage and a color (white by default), and send the bordered images to a board or a folder. Output keeps the native resolution, color space, bit depth and file format.

**Architecture:**
- A pure, `nonisolated` CoreGraphics/ImageIO renderer (`BorderRenderer`) pads each image into a bitmap context that matches the source's pixel format and re-encodes it in the source's type.
- A thin main-actor `BorderToolService` loads sources from files or drops and rasterizes SVGs, then runs the renderer off-main.
- The sheet (`BorderToolView`) sends results either through a new shared `ImageImportService.insertImage` (board) or writes uniquely named files (folder). A `Tools` command menu opens it via a focused-scene binding published by `RootView`.

**Tech Stack:** Swift, SwiftUI, AppKit (`NSOpenPanel`, `NSItemProvider`), CoreGraphics, ImageIO, SwiftData, Swift Testing, XCTest (UI).

**Spec:** `docs/superpowers/specs/2026-10-10-white-border-design.md`

## Global Constraints

- macOS 27, Xcode 27. `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so off-main types must be `nonisolated` (as `FileStorageService` is).
- New files in `moody/`, `moodyTests/` or `moodyUITests/` are picked up automatically, so don't edit `project.pbxproj`. The sandbox already has `ENABLE_USER_SELECTED_FILES = readwrite`.
- Lint must pass: `swiftformat --lint .` and `swiftlint lint --strict`. The rules are 4-space indent, 140-col lines, mandatory trailing commas in multi-line collections, `@testable import` last, and `large_tuple` warns above 3 members.
- Border width is `Int((Double(max(w, h)) * percent / 100).rounded())`, applied on all 4 sides. Range 0–50%, default 5%.
- Border color comes from `ColorPicker(supportsOpacity: false)` and defaults to white.
- The output has the same pixel content (no resampling) and the same color space and bit depth as the source. It's re-encoded in the source type when ImageIO can write it, otherwise PNG. Lossy quality is `1.0`.
- A grayscale source with a non-neutral border color falls back to sRGB at the source bit depth.
- Folder files are named `<name> border.<ext>`, then `<name> border 2.<ext>`, and so on. They're never overwritten.
- Copy:
  - Menu "Tools" / "Add Border…"; sheet title "Add Border".
  - Buttons "Choose Images…", "Cancel", "Add to Board" or "Save…"; panel prompts "Add" (files) and "Save" (folder).
  - Drop hint "Drop images here".
  - Alerts "N images couldn't be added." / "N images couldn't be bordered." (singular "1 image …").
- **Don't commit.** The user commits their own work. There are no `git add`/`git commit` steps.

## Review Focus

1. **Exporting the same files twice into one folder** must produce `… border 2.ext`, never replace the first export, even when only the case differs. *(Task 4 tests + `.withoutOverwriting` in Task 5)*
2. **A grayscale photo with a colored border** must keep the color, not come out gray. *(Task 1 test)*
3. **A PNG with transparency** must stay transparent inside the photo while the border is opaque. *(Task 1 test)*
4. **A phone JPEG with an EXIF rotation** must keep its orientation tag. The border is uniform, so the result is still correct. *(Task 1 test)*
5. **One unreadable or failing file in a batch** must not stop the others, and the failed ones must stay in the list so they can be retried. *(Task 5 code + manual QA step 5)*

---

### Task 1: BorderRenderer — pad and re-encode at native quality

**Files:**
- Create: `moody/Import/BorderRenderer.swift`
- Create: `moodyTests/ImageFixtures.swift`
- Test: `moodyTests/BorderRendererTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `nonisolated struct BorderedImage { let data: Data; let contentType: UTType; let pixelWidth: Int; let pixelHeight: Int; var fileExtension: String }`
  - `nonisolated enum BorderRenderError: Error { case undecodableImage, unsupportedPixelFormat, encodingFailed }`
  - `BorderRenderer.borderWidth(pixelWidth: Int, pixelHeight: Int, percent: Double) -> Int`
  - `BorderRenderer.outputType(for: UTType) -> UTType`
  - `BorderRenderer.addBorder(to data: Data, percent: Double, color: CGColor) throws -> BorderedImage`. The format is read from the data itself (`CGImageSourceGetType`), so a drop that only reported `public.image` still keeps its JPEG/PNG type.
  - Test helpers: `ImageFixtures.make(...)`, `ImageFixtures.decoded(_:)`, `ImageFixtures.pixel(_:x:y:)`, `ImageFixtures.imageType(of:)`.

- [ ] **Step 1: Write the test fixtures**

`moodyTests/ImageFixtures.swift`:

```swift
//
//  ImageFixtures.swift
//  moodyTests
//
//  In-memory test images: encode a flat-filled image in any format / pixel
//  format, and read back decoded pixels in a fixed RGBA8 sRGB layout.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

enum ImageFixtures {
    static var sRGB: CGColorSpace {
        CGColorSpace(name: CGColorSpace.sRGB)!
    }

    static var red: CGColor {
        CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    }

    static var white: CGColor {
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    }

    /// Encodes a `width`×`height` image filled with `fill` (nil leaves it fully transparent).
    static func make(
        width: Int = 100,
        height: Int = 50,
        type: UTType = .png,
        space: CGColorSpace = ImageFixtures.sRGB,
        bitsPerComponent: Int = 8,
        alpha: CGImageAlphaInfo = .noneSkipLast,
        fill: CGColor?,
        properties: [CFString: Any] = [:]
    ) throws -> Data {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: alpha.rawValue
        ))
        if let fill {
            context.setFillColor(fill)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    static func decoded(_ data: Data) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    static func imageType(of data: Data) throws -> UTType? {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return CGImageSourceGetType(source).flatMap { UTType($0 as String) }
    }

    /// RGBA8 sRGB bytes of the pixel at (x, y), with y counted from the top.
    static func pixel(_ data: Data, x: Int, y: Int) throws -> [UInt8] {
        let image = try decoded(data)
        let context = try #require(CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = y * image.width * 4 + x * 4
        return (0 ..< 4).map { bytes[offset + $0] }
    }
}
```

- [ ] **Step 2: Write the failing renderer tests**

`moodyTests/BorderRendererTests.swift`:

```swift
//
//  BorderRendererTests.swift
//  moodyTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import moody

struct BorderRendererTests {
    private let white: [UInt8] = [255, 255, 255, 255]
    private let red: [UInt8] = [255, 0, 0, 255]

    private func isClose(_ lhs: [UInt8], _ rhs: [UInt8], tolerance: Int = 3) -> Bool {
        zip(lhs, rhs).allSatisfy { abs(Int($0) - Int($1)) <= tolerance }
    }

    // MARK: - borderWidth

    @Test func borderWidthIsAPercentOfTheLongEdge() {
        #expect(BorderRenderer.borderWidth(pixelWidth: 4000, pixelHeight: 3000, percent: 5) == 200)
        #expect(BorderRenderer.borderWidth(pixelWidth: 3000, pixelHeight: 4000, percent: 5) == 200)
        #expect(BorderRenderer.borderWidth(pixelWidth: 1000, pixelHeight: 1000, percent: 10) == 100)
    }

    @Test func borderWidthRoundsToTheNearestPixel() {
        #expect(BorderRenderer.borderWidth(pixelWidth: 333, pixelHeight: 100, percent: 1) == 3)
        #expect(BorderRenderer.borderWidth(pixelWidth: 350, pixelHeight: 100, percent: 1) == 4)
    }

    @Test func zeroPercentGivesNoBorder() {
        #expect(BorderRenderer.borderWidth(pixelWidth: 4000, pixelHeight: 3000, percent: 0) == 0)
    }

    // MARK: - outputType

    @Test func outputTypeKeepsWritableTypesAndFallsBackToPNG() {
        #expect(BorderRenderer.outputType(for: .jpeg) == .jpeg)
        #expect(BorderRenderer.outputType(for: .svg) == .png)
    }

    // MARK: - addBorder geometry and pixels

    @Test func outputGrowsByTheBorderOnEverySide() throws {
        let output = try BorderRenderer.addBorder(to: ImageFixtures.make(fill: ImageFixtures.red), percent: 10, color: ImageFixtures.white)
        #expect(output.pixelWidth == 120)
        #expect(output.pixelHeight == 70)
        let image = try ImageFixtures.decoded(output.data)
        #expect(image.width == 120)
        #expect(image.height == 70)
    }

    @Test func borderIsWhiteAndThePhotoIsUntouched() throws {
        // 100×50 at 10% → 10 px border; photo spans x 10...109, y 10...59.
        let output = try BorderRenderer.addBorder(to: ImageFixtures.make(fill: ImageFixtures.red), percent: 10, color: ImageFixtures.white)
        #expect(try ImageFixtures.pixel(output.data, x: 0, y: 0) == white)
        #expect(try ImageFixtures.pixel(output.data, x: 119, y: 69) == white)
        #expect(try ImageFixtures.pixel(output.data, x: 9, y: 35) == white)
        #expect(try ImageFixtures.pixel(output.data, x: 110, y: 35) == white)
        #expect(try ImageFixtures.pixel(output.data, x: 10, y: 10) == red)
        #expect(try ImageFixtures.pixel(output.data, x: 109, y: 59) == red)
    }

    @Test func borderUsesTheChosenColor() throws {
        let blue = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        let output = try BorderRenderer.addBorder(to: ImageFixtures.make(fill: ImageFixtures.red), percent: 10, color: blue)
        #expect(try ImageFixtures.pixel(output.data, x: 0, y: 0) == [0, 0, 255, 255])
        #expect(try ImageFixtures.pixel(output.data, x: 10, y: 10) == red)
    }

    @Test func transparentPhotoPixelsStayTransparent() throws {
        let data = try ImageFixtures.make(alpha: .premultipliedLast, fill: nil)
        let output = try BorderRenderer.addBorder(to: data, percent: 10, color: ImageFixtures.white)
        #expect(try ImageFixtures.pixel(output.data, x: 50, y: 30)[3] == 0)
        #expect(try ImageFixtures.pixel(output.data, x: 0, y: 0) == white)
    }

    // MARK: - format and quality

    @Test func pngStaysPNGAndJPEGStaysJPEG() throws {
        let png = try BorderRenderer.addBorder(to: ImageFixtures.make(fill: ImageFixtures.red), percent: 5, color: ImageFixtures.white)
        #expect(png.contentType == .png)
        #expect(try ImageFixtures.imageType(of: png.data) == .png)

        let jpegSource = try ImageFixtures.make(type: .jpeg, fill: ImageFixtures.red)
        let jpeg = try BorderRenderer.addBorder(to: jpegSource, percent: 5, color: ImageFixtures.white)
        #expect(jpeg.contentType == .jpeg)
        #expect(try ImageFixtures.imageType(of: jpeg.data) == .jpeg)
    }

    @Test func jpegKeepsBorderAndPhotoColorsAtMaximumQuality() throws {
        let jpegSource = try ImageFixtures.make(type: .jpeg, fill: ImageFixtures.red)
        let output = try BorderRenderer.addBorder(to: jpegSource, percent: 10, color: ImageFixtures.white)
        #expect(isClose(try ImageFixtures.pixel(output.data, x: 2, y: 2), white))
        #expect(isClose(try ImageFixtures.pixel(output.data, x: 60, y: 35), red))
    }

    @Test func sixteenBitPNGStaysSixteenBit() throws {
        let data = try ImageFixtures.make(bitsPerComponent: 16, fill: ImageFixtures.red)
        #expect(try ImageFixtures.decoded(data).bitsPerComponent == 16) // the fixture really is 16-bit
        let output = try BorderRenderer.addBorder(to: data, percent: 5, color: ImageFixtures.white)
        #expect(try ImageFixtures.decoded(output.data).bitsPerComponent == 16)
    }

    @Test func colorProfileIsPreserved() throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let data = try ImageFixtures.make(space: p3, fill: try #require(CGColor(colorSpace: p3, components: [1, 0, 0, 1])))
        let output = try BorderRenderer.addBorder(to: data, percent: 5, color: ImageFixtures.white)
        let sourceICC = try ImageFixtures.decoded(data).colorSpace?.copyICCData() as Data?
        let outputICC = try ImageFixtures.decoded(output.data).colorSpace?.copyICCData() as Data?
        #expect(sourceICC != nil)
        #expect(outputICC == sourceICC)
    }

    @Test func exifOrientationIsKept() throws {
        let data = try ImageFixtures.make(type: .jpeg, fill: ImageFixtures.red, properties: [kCGImagePropertyOrientation: 6])
        let output = try BorderRenderer.addBorder(to: data, percent: 5, color: ImageFixtures.white)
        let source = try #require(CGImageSourceCreateWithData(output.data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyOrientation] as? Int == 6)
    }

    // MARK: - grayscale

    @Test func grayscaleWithWhiteBorderStaysGrayscale() throws {
        let gray = try #require(CGColorSpace(name: CGColorSpace.genericGrayGamma2_2))
        let data = try ImageFixtures.make(space: gray, alpha: .none, fill: CGColor(gray: 0.5, alpha: 1))
        let output = try BorderRenderer.addBorder(to: data, percent: 10, color: ImageFixtures.white)
        #expect(try ImageFixtures.decoded(output.data).colorSpace?.model == .monochrome)
        #expect(try ImageFixtures.pixel(output.data, x: 0, y: 0) == white)
    }

    @Test func grayscaleWithColoredBorderBecomesRGB() throws {
        let gray = try #require(CGColorSpace(name: CGColorSpace.genericGrayGamma2_2))
        let data = try ImageFixtures.make(space: gray, alpha: .none, fill: CGColor(gray: 0.5, alpha: 1))
        let output = try BorderRenderer.addBorder(to: data, percent: 10, color: ImageFixtures.red)
        #expect(try ImageFixtures.decoded(output.data).colorSpace?.model == .rgb)
        #expect(try ImageFixtures.pixel(output.data, x: 0, y: 0) == red)
    }

    // MARK: - errors

    @Test func undecodableDataThrows() {
        #expect(throws: BorderRenderError.undecodableImage) {
            try BorderRenderer.addBorder(to: Data("not an image".utf8), percent: 5, color: ImageFixtures.white)
        }
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/BorderRendererTests`
Expected: build FAILS with "cannot find 'BorderRenderer' in scope".

- [ ] **Step 4: Implement the renderer**

`moody/Import/BorderRenderer.swift`:

```swift
//
//  BorderRenderer.swift
//  moody
//
//  Pads an image with a solid border without touching its pixels: the
//  canvas matches the source's color space, bit depth and alpha, the photo
//  is copied in at an integer offset with no interpolation, and the result
//  is re-encoded in the source's own format with its metadata. Pure and
//  nonisolated so it can run off the main actor.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct BorderedImage {
    let data: Data
    let contentType: UTType
    let pixelWidth: Int
    let pixelHeight: Int

    var fileExtension: String {
        contentType.preferredFilenameExtension ?? "png"
    }
}

nonisolated enum BorderRenderError: Error {
    case undecodableImage
    case unsupportedPixelFormat
    case encodingFailed
}

nonisolated enum BorderRenderer {
    static func borderWidth(pixelWidth: Int, pixelHeight: Int, percent: Double) -> Int {
        Int((Double(max(pixelWidth, pixelHeight)) * percent / 100).rounded())
    }

    /// The source's type when ImageIO can write it (JPEG, PNG, HEIC, TIFF…), otherwise PNG.
    static func outputType(for contentType: UTType) -> UTType {
        let writable = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return writable.contains(contentType.identifier) ? contentType : .png
    }

    static func addBorder(to data: Data, percent: Double, color: CGColor) throws -> BorderedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw BorderRenderError.undecodableImage
        }

        let border = borderWidth(pixelWidth: image.width, pixelHeight: image.height, percent: percent)
        let width = image.width + 2 * border
        let height = image.height + 2 * border
        guard let context = makeContext(matching: image, width: width, height: height, borderColor: color) else {
            throw BorderRenderError.unsupportedPixelFormat
        }

        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // .copy + no interpolation at an integer offset: the photo's pixels land unchanged, transparency included.
        context.setBlendMode(.copy)
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: border, y: border, width: image.width, height: image.height))
        guard let bordered = context.makeImage() else {
            throw BorderRenderError.unsupportedPixelFormat
        }

        let sourceType = CGImageSourceGetType(source).flatMap { UTType($0 as String) } ?? .png
        let type = outputType(for: sourceType)
        let encoded = try encode(bordered, as: type, sourceProperties: CGImageSourceCopyPropertiesAtIndex(source, 0, nil))
        return BorderedImage(data: encoded, contentType: type, pixelWidth: width, pixelHeight: height)
    }

    /// A bitmap context in the source's own color space and depth. Falls back to
    /// sRGB at the source's depth when the source can't back a context (indexed,
    /// gray + alpha, …) or is grayscale with a border color that has a hue.
    private static func makeContext(matching image: CGImage, width: Int, height: Int, borderColor: CGColor) -> CGContext? {
        let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let isFloat = image.bitmapInfo.contains(.floatComponents)
        if let space = image.colorSpace,
           !(space.model == .monochrome && !isNeutral(borderColor)),
           let info = bitmapInfo(model: space.model, hasAlpha: hasAlpha, isFloat: isFloat),
           let context = CGContext(
               data: nil,
               width: width,
               height: height,
               bitsPerComponent: image.bitsPerComponent,
               bytesPerRow: 0,
               space: space,
               bitmapInfo: info
           ) {
            return context
        }
        let alpha: CGImageAlphaInfo = hasAlpha ? .premultipliedLast : .noneSkipLast
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: image.bitsPerComponent >= 16 ? 16 : 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: alpha.rawValue
        )
    }

    /// Bitmap-context layouts CoreGraphics supports for each color model; nil means "use the fallback".
    private static func bitmapInfo(model: CGColorSpaceModel, hasAlpha: Bool, isFloat: Bool) -> UInt32? {
        let alpha: CGImageAlphaInfo
        switch (model, hasAlpha) {
        case (.rgb, true), (.monochrome, true):
            alpha = .premultipliedLast
        case (.rgb, false):
            alpha = .noneSkipLast
        case (.monochrome, false), (.cmyk, false):
            alpha = .none
        default:
            return nil
        }
        return alpha.rawValue | (isFloat ? CGBitmapInfo.floatComponents.rawValue : 0)
    }

    /// White, black and grays survive a grayscale canvas without losing their hue.
    private static func isNeutral(_ color: CGColor) -> Bool {
        guard let rgb = color.converted(to: CGColorSpace(name: CGColorSpace.extendedSRGB)!, intent: .defaultIntent, options: nil)?
            .components,
            rgb.count >= 3
        else {
            return false
        }
        return max(abs(rgb[0] - rgb[1]), abs(rgb[1] - rgb[2])) < 1.0 / 255
    }

    private static func encode(_ image: CGImage, as type: UTType, sourceProperties: CFDictionary?) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            throw BorderRenderError.encodingFailed
        }
        // Keep EXIF, orientation, DPI etc.; the size keys described the unbordered image.
        var properties = (sourceProperties as? [CFString: Any]) ?? [:]
        properties[kCGImagePropertyPixelWidth] = nil
        properties[kCGImagePropertyPixelHeight] = nil
        properties[kCGImageDestinationLossyCompressionQuality] = 1.0
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw BorderRenderError.encodingFailed
        }
        return output as Data
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/BorderRendererTests`
Expected: all PASS.

If `grayscaleWithWhiteBorderStaysGrayscale` reads 254 instead of 255 at the border, ColorSync isn't mapping sRGB white exactly onto gray white. In `addBorder`, fill with a color already in the canvas space: `context.setFillColor(color.converted(to: context.colorSpace!, intent: .absoluteColorimetric, options: nil) ?? color)`. Then re-run. Don't loosen the test: a white border must be pure white.

- [ ] **Step 6: Lint**

Run: `swiftformat . && swiftformat --lint . && swiftlint lint --strict`
Expected: no violations.

---

### Task 2: Shared board insert in ImageImportService

**Files:**
- Modify: `moody/Import/ImageImportService.swift`
- Test: `moodyTests/ImageImportServiceTests.swift` (new)

**Interfaces:**
- Consumes: `FileStorageService`, `aspectFit`, `nextZIndex`, `BoardItem`, `Project`.
- Produces:
  - `ImageImportService.maxDisplayEdge` (`static let`, now internal).
  - `@MainActor ImageImportService.insertImage(data: Data, fileExtension: String, pixelWidth: Int, pixelHeight: Int, into: Project, at: CGPoint, context: ModelContext, storage: FileStorageService = FileStorageService()) throws`
  - `ImageImportService.loadFileRepresentation(_ provider: NSItemProvider) async throws -> (data: Data, contentType: UTType)` (now internal).
  - `ImageImportService.contentType(of url: URL) -> UTType`

- [ ] **Step 1: Write the failing test**

`moodyTests/ImageImportServiceTests.swift`:

```swift
//
//  ImageImportServiceTests.swift
//  moodyTests
//

import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import moody

@MainActor
struct ImageImportServiceTests {
    @Test func insertImageWritesTheFileAndAddsAnItemToTheBoard() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("moody-tests-\(UUID().uuidString)", isDirectory: true)
        let storage = FileStorageService(rootDirectory: root)
        let container = try ModelContainer(
            for: Folder.self, Project.self, BoardItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let project = Project(name: "Board")
        context.insert(project)

        try ImageImportService.insertImage(
            data: Data("png-bytes".utf8),
            fileExtension: "png",
            pixelWidth: 640,
            pixelHeight: 320,
            into: project,
            at: CGPoint(x: 10, y: 20),
            context: context,
            storage: storage
        )

        #expect(project.items.count == 1)
        let item = try #require(project.items.first)
        #expect(item.positionX == 10)
        #expect(item.positionY == 20)
        #expect(item.width == 320)
        #expect(item.height == 160)
        #expect(item.pixelWidth == 640)
        #expect(item.fileName.hasSuffix(".png"))
        #expect(FileManager.default.fileExists(atPath: storage.fileURL(fileName: item.fileName, projectID: project.id).path))
    }

    @Test func contentTypeOfAFileComesFromItsExtension() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try Data("x".utf8).write(to: url)
        #expect(ImageImportService.contentType(of: url) == .png)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/ImageImportServiceTests`
Expected: build FAILS with "type 'ImageImportService' has no member 'insertImage'".

- [ ] **Step 3: Refactor `ImageImportService`**

In `moody/Import/ImageImportService.swift`:

1. Change `private static let maxDisplayEdge: Double = 320` to `static let maxDisplayEdge: Double = 320`.
2. In `importOne`, replace everything from `let itemID = UUID()` to the end of the function with:

```swift
        try insertImage(
            data: finalData,
            fileExtension: fileExtension,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            into: project,
            at: position,
            context: context,
            storage: storage
        )
    }

    /// Writes the file to the board's storage and inserts its `BoardItem` on top.
    /// Shared by board drops and the Add Border tool.
    @MainActor
    static func insertImage(
        data: Data,
        fileExtension: String,
        pixelWidth: Int,
        pixelHeight: Int,
        into project: Project,
        at position: CGPoint,
        context: ModelContext,
        storage: FileStorageService = FileStorageService()
    ) throws {
        let itemID = UUID()
        let fileName = "\(itemID.uuidString).\(fileExtension)"
        try storage.write(data: data, fileName: fileName, projectID: project.id)

        let displaySize = aspectFit(pixelWidth: pixelWidth, pixelHeight: pixelHeight, maxEdge: maxDisplayEdge)
        let zIndex = nextZIndex(existing: project.items.map(\.zIndex))

        let item = BoardItem(
            id: itemID,
            fileName: fileName,
            positionX: position.x,
            positionY: position.y,
            width: displaySize.width,
            height: displaySize.height,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            zIndex: zIndex,
            project: project
        )
        context.insert(item)
        try context.save()
    }
```

3. Change `private static func loadFileRepresentation` to `static func loadFileRepresentation`. Inside it, replace the three-line `let contentType = (try? url.resourceValues(...` expression with `let contentType = ImageImportService.contentType(of: url)` (qualified: an unqualified call would collide with the local `contentType` being declared).
4. Add after `loadFileRepresentation`:

```swift
    /// The file's type from its resource values, then its extension, else generic image.
    static func contentType(of url: URL) -> UTType {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
            ?? .image
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/ImageImportServiceTests`
Expected: PASS.

- [ ] **Step 5: Lint**

Run: `swiftformat . && swiftformat --lint . && swiftlint lint --strict`
Expected: no violations.

---

### Task 3: Placement right of existing board content

**Files:**
- Modify: `moody/Import/ImportGeometry.swift`
- Test: `moodyTests/ImportGeometryTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `appendedImportCenter(contentBounds: CGRect?, size: CGSize, gap: Double = 40) -> CGPoint`. Calling it once per image, with bounds recomputed after each insert, lays a batch out in a row.

- [ ] **Step 1: Write the failing tests**

Append inside `struct ImportGeometryTests` in `moodyTests/ImportGeometryTests.swift`:

```swift
    // MARK: - appendedImportCenter

    @Test func appendedImportCenterPutsTheTopLeftAtTheOriginOnAnEmptyBoard() {
        let center = appendedImportCenter(contentBounds: nil, size: CGSize(width: 200, height: 100))
        #expect(center == CGPoint(x: 100, y: 50))
    }

    @Test func appendedImportCenterPlacesTheImageRightOfContentTopAligned() {
        let bounds = CGRect(x: -50, y: 10, width: 300, height: 400)
        let center = appendedImportCenter(contentBounds: bounds, size: CGSize(width: 200, height: 100), gap: 40)
        #expect(center == CGPoint(x: 390, y: 60))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/ImportGeometryTests`
Expected: build FAILS with "cannot find 'appendedImportCenter' in scope".

- [ ] **Step 3: Implement**

Append to `moody/Import/ImportGeometry.swift`:

```swift
/// Center for an image of `size` placed `gap` to the right of the board's
/// existing content, top-aligned with it. Recomputing the bounds after each
/// insert lays a batch out in a row. An empty board puts the top-left at the origin.
func appendedImportCenter(contentBounds: CGRect?, size: CGSize, gap: Double = 40) -> CGPoint {
    let topLeft = contentBounds.map { CGPoint(x: $0.maxX + gap, y: $0.minY) } ?? .zero
    return CGPoint(x: topLeft.x + size.width / 2, y: topLeft.y + size.height / 2)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/ImportGeometryTests`
Expected: PASS.

---

### Task 4: BorderToolService — sources, SVGs, off-main render, unique names

**Files:**
- Create: `moody/Import/BorderToolService.swift`
- Test: `moodyTests/BorderToolServiceTests.swift`

**Interfaces:**
- Consumes:
  - `BorderRenderer.addBorder(to:percent:color:)` and `BorderedImage` (Task 1).
  - `ImageImportService.loadFileRepresentation(_:)` and `ImageImportService.contentType(of:)` (Task 2).
  - `SVGRasterizer.rasterize(svgData:maxEdge:) async throws -> (pngData: Data, pixelWidth: Int, pixelHeight: Int)` (existing).
- Produces:
  - `struct BorderSource: Identifiable { let id: UUID; let name: String; let data: Data; let contentType: UTType }`. `name` has no extension.
  - `BorderToolService.loadSource(at url: URL) throws -> BorderSource`
  - `BorderToolService.loadSource(from provider: NSItemProvider) async throws -> BorderSource`
  - `BorderToolService.render(_ source: BorderSource, percent: Double, color: CGColor) async throws -> BorderedImage`
  - `uniqueBorderFileName(base: String, fileExtension: String, taken: Set<String>) -> String`. `taken` holds **lowercased** names.

- [ ] **Step 1: Write the failing tests**

`moodyTests/BorderToolServiceTests.swift`:

```swift
//
//  BorderToolServiceTests.swift
//  moodyTests
//

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import moody

@MainActor
struct BorderToolServiceTests {
    // MARK: - uniqueBorderFileName

    @Test func uniqueNameAddsTheBorderSuffix() {
        #expect(uniqueBorderFileName(base: "Beach", fileExtension: "jpg", taken: []) == "Beach border.jpg")
    }

    @Test func uniqueNameSkipsATakenNameIgnoringCase() {
        let name = uniqueBorderFileName(base: "Beach", fileExtension: "jpg", taken: ["beach border.jpg"])
        #expect(name == "Beach border 2.jpg")
    }

    @Test func uniqueNameKeepsCountingPastTakenNumbers() {
        let taken: Set<String> = ["beach border.jpg", "beach border 2.jpg"]
        #expect(uniqueBorderFileName(base: "Beach", fileExtension: "jpg", taken: taken) == "Beach border 3.jpg")
    }

    // MARK: - loadSource

    @Test func loadingAFileKeepsItsBytesTypeAndNameWithoutExtension() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("moody-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Beach.png")
        let data = try ImageFixtures.make(fill: ImageFixtures.red)
        try data.write(to: url)

        let source = try BorderToolService.loadSource(at: url)

        #expect(source.name == "Beach")
        #expect(source.contentType == .png)
        #expect(source.data == data)
    }

    // MARK: - render

    @Test func renderBordersARasterSource() async throws {
        let source = BorderSource(name: "Red", data: try ImageFixtures.make(fill: ImageFixtures.red), contentType: .png)
        let output = try await BorderToolService.render(source, percent: 10, color: ImageFixtures.white)
        #expect(output.pixelWidth == 120)
        #expect(output.pixelHeight == 70)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/BorderToolServiceTests`
Expected: build FAILS with "cannot find 'uniqueBorderFileName' in scope".

- [ ] **Step 3: Implement**

`moody/Import/BorderToolService.swift`:

```swift
//
//  BorderToolService.swift
//  moody
//
//  Glue for the Add Border tool: reads sources from files or drops (bytes
//  are kept, so nothing depends on a sandbox-scoped URL staying readable),
//  rasterizes SVGs on the main actor, and runs BorderRenderer off it.
//

import AppKit
import CoreGraphics
import UniformTypeIdentifiers

struct BorderSource: Identifiable {
    let id = UUID()
    /// File name without extension; outputs are named after it.
    let name: String
    let data: Data
    let contentType: UTType
}

enum BorderToolService {
    static func loadSource(at url: URL) throws -> BorderSource {
        BorderSource(
            name: url.deletingPathExtension().lastPathComponent,
            data: try Data(contentsOf: url),
            contentType: ImageImportService.contentType(of: url)
        )
    }

    static func loadSource(from provider: NSItemProvider) async throws -> BorderSource {
        let (data, contentType) = try await ImageImportService.loadFileRepresentation(provider)
        let name = ((provider.suggestedName ?? "Image") as NSString).deletingPathExtension
        return BorderSource(name: name, data: data, contentType: contentType)
    }

    static func render(_ source: BorderSource, percent: Double, color: CGColor) async throws -> BorderedImage {
        let input: Data
        if source.contentType.conforms(to: .svg) {
            // WKWebView rasterizing needs the main actor; the pixel work below doesn't.
            input = try await SVGRasterizer.rasterize(svgData: source.data).pngData
        } else {
            input = source.data
        }
        return try await Task.detached {
            try BorderRenderer.addBorder(to: input, percent: percent, color: color)
        }.value
    }
}

/// "<base> border.<ext>", else "<base> border 2.<ext>", "… 3" …: the first name not in
/// `taken`. `taken` holds lowercased names, since the macOS file system ignores case by default.
func uniqueBorderFileName(base: String, fileExtension: String, taken: Set<String>) -> String {
    var counter = 1
    while true {
        let suffix = counter == 1 ? "border" : "border \(counter)"
        let name = "\(base) \(suffix).\(fileExtension)"
        if !taken.contains(name.lowercased()) {
            return name
        }
        counter += 1
    }
}
```

If the compiler reports that `CGColor` isn't `Sendable` when it's captured by `Task.detached`, add `nonisolated(unsafe) let color = color` as the first line of `render`. `CGColor` is immutable, so sharing it is safe.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyTests/BorderToolServiceTests`
Expected: PASS.

- [ ] **Step 5: Lint**

Run: `swiftformat . && swiftformat --lint . && swiftlint lint --strict`
Expected: no violations.

---

### Task 5: Add Border sheet, Tools menu and wiring

**Files:**
- Create: `moody/Views/Border/BorderToolView.swift`
- Create: `moody/Views/Border/BorderToolCommands.swift`
- Modify: `moody/Views/RootView.swift`
- Modify: `moody/moodyApp.swift`
- Test: `moodyUITests/BorderToolUITests.swift` (new)

**Interfaces:**
- Consumes:
  - `BorderSource`, `BorderToolService.loadSource(at:)`, `.loadSource(from:)`, `.render(_:percent:color:)` and `uniqueBorderFileName(base:fileExtension:taken:)` (Task 4).
  - `BorderedImage` (Task 1).
  - `ImageImportService.insertImage(...)` and `ImageImportService.maxDisplayEdge` (Task 2).
  - `appendedImportCenter(contentBounds:size:)` (Task 3), plus the existing `boardContentBounds(_:)` and `aspectFit(...)`.
- Produces: `BorderToolView(defaultBoardID: UUID?)`, `BorderToolCommands`, `FocusedValues.showsBorderTool: Binding<Bool>?`.

- [ ] **Step 1: Write the failing UI test**

`moodyUITests/BorderToolUITests.swift`:

```swift
//
//  BorderToolUITests.swift
//  moodyUITests
//
//  Tools ▸ Add Border… opens its sheet from the keyboard and Cancel closes it.
//  Launches with -inMemoryStore so the user's real library is untouched.
//

import XCTest

final class BorderToolUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    func testShortcutOpensTheSheetAndCancelClosesIt() {
        app.typeKey("b", modifierFlags: [.command, .shift])
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 3))
        XCTAssertTrue(sheet.buttons["Choose Images…"].exists)

        sheet.buttons["Cancel"].click()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 3))
    }
}
```

- [ ] **Step 2: Run the UI test to verify it fails**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyUITests/BorderToolUITests`
Expected: FAIL, because `sheet.waitForExistence` returns false.

- [ ] **Step 3: Add the command and focused value**

`moody/Views/Border/BorderToolCommands.swift`:

```swift
//
//  BorderToolCommands.swift
//  moody
//
//  Tools ▸ Add Border… (⇧⌘B). The flag lives in the focused window's
//  RootView, so the sheet opens there and knows that window's open board.
//

import SwiftUI

extension FocusedValues {
    @Entry var showsBorderTool: Binding<Bool>?
}

struct BorderToolCommands: Commands {
    @FocusedBinding(\.showsBorderTool) private var showsBorderTool

    var body: some Commands {
        CommandMenu("Tools") {
            Button("Add Border…") {
                showsBorderTool = true
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(showsBorderTool == nil)
        }
    }
}
```

In `moody/moodyApp.swift`, add `.commands { BorderToolCommands() }` to the `WindowGroup`, after `.modelContainer(sharedModelContainer)`:

```swift
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
        .commands {
            BorderToolCommands()
        }
```

- [ ] **Step 4: Present the sheet from RootView**

In `moody/Views/RootView.swift`:

- Add `@State private var isShowingBorderTool = false` below `@State private var selection`.
- Chain onto the `NavigationSplitView { … } detail: { … }` in `body`:

```swift
        .focusedSceneValue(\.showsBorderTool, $isShowingBorderTool)
        .sheet(isPresented: $isShowingBorderTool) {
            BorderToolView(defaultBoardID: selectedBoardID)
        }
```

- Add below `body`:

```swift
    /// The open board, offered as the Add Border tool's default destination.
    private var selectedBoardID: UUID? {
        if case let .board(id) = selection { id } else { nil }
    }
```

- [ ] **Step 5: Build the sheet**

`moody/Views/Border/BorderToolView.swift`:

```swift
//
//  BorderToolView.swift
//  moody
//
//  Tools ▸ Add Border…: images dropped on the sheet or chosen from disk get a
//  border (percent of the long edge, any opaque color) and go to a board or a
//  folder. Pixels, format and quality are handled by BorderRenderer.
//

import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BorderToolView: View {
    private enum Destination: Hashable {
        case board
        case folder
    }

    private enum Target {
        case board(Project)
        case folder(URL)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.self) private var environment
    @Query(sort: \Project.name) private var projects: [Project]
    @State private var sources: [BorderSource] = []
    @State private var preview: NSImage?
    @State private var percent: Double = 5
    @State private var color: Color = .white
    @State private var destination: Destination = .board
    @State private var boardID: UUID?
    @State private var isDropTargeted = false
    @State private var isWorking = false
    @State private var failureMessage = ""
    @State private var isShowingFailure = false

    init(defaultBoardID: UUID?) {
        _boardID = State(initialValue: defaultBoardID)
    }

    private var canApply: Bool {
        !sources.isEmpty && !isWorking && (destination == .folder || boardID != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Border")
                .font(.headline)
            dropZone
            Form {
                LabeledContent("Border") {
                    HStack {
                        Slider(value: $percent, in: 0 ... 50)
                        TextField("Border", value: $percent, format: .number.precision(.fractionLength(0 ... 1)))
                            .labelsHidden()
                            .frame(width: 48)
                        Text("%")
                    }
                }
                ColorPicker("Color", selection: $color, supportsOpacity: false)
                Picker("Destination", selection: $destination) {
                    Text("Board").tag(Destination.board)
                    Text("Folder").tag(Destination.folder)
                }
                .pickerStyle(.segmented)
                if destination == .board {
                    Picker("Board", selection: $boardID) {
                        ForEach(projects) { project in
                            Text(project.name).tag(Optional(project.id))
                        }
                    }
                }
            }
            HStack {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isWorking)
                Button(destination == .board ? "Add to Board" : "Save…") {
                    Task { await apply() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canApply)
            }
        }
        .padding(20)
        .frame(width: 460)
        .interactiveDismissDisabled(isWorking)
        .onDrop(of: [.image], isTargeted: $isDropTargeted) { providers in
            Task { await add(providers) }
            return true
        }
        .onAppear {
            if boardID == nil {
                boardID = projects.first?.id
            }
            if projects.isEmpty {
                destination = .folder
            }
        }
        .onChange(of: percent) {
            percent = min(max(percent, 0), 50)
        }
        .onChange(of: sources.first?.id) {
            // Decoded once per first-image change, not on every render.
            preview = sources.first.flatMap { NSImage(data: $0.data) }
        }
        .alert(failureMessage, isPresented: $isShowingFailure) {
            Button("OK") {}
        }
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            if let preview {
                let fit = aspectFit(pixelWidth: Int(preview.size.width), pixelHeight: Int(preview.size.height), maxEdge: 160)
                // Display only: the padding mirrors the percent of the long edge.
                Image(nsImage: preview)
                    .resizable()
                    .frame(width: fit.width, height: fit.height)
                    .padding(max(fit.width, fit.height) * percent / 100)
                    .background(color)
                    .shadow(radius: 2)
            }
            if sources.isEmpty {
                Text("Drop images here")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(sources) { source in
                            HStack {
                                Text(source.name)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button("Remove", systemImage: "xmark.circle.fill") {
                                    sources.removeAll { $0.id == source.id }
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .frame(maxHeight: 100)
            }
            Button("Choose Images…", action: chooseImages)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [5])
                )
        )
    }

    private func chooseImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        var failed = 0
        for url in panel.urls {
            do {
                try sources.append(BorderToolService.loadSource(at: url))
            } catch {
                failed += 1
            }
        }
        reportFailures(failed, "couldn't be added")
    }

    private func add(_ providers: [NSItemProvider]) async {
        var failed = 0
        for provider in providers {
            do {
                try await sources.append(BorderToolService.loadSource(from: provider))
            } catch {
                failed += 1
            }
        }
        reportFailures(failed, "couldn't be added")
    }

    private func apply() async {
        guard let target = resolveTarget() else { return }
        let borderColor = color.resolve(in: environment).cgColor
        var taken = Set<String>()
        if case let .folder(folder) = target {
            let existing = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            taken = Set(existing.map { $0.lowercased() })
        }
        isWorking = true
        var failedSources: [BorderSource] = []
        for source in sources {
            do {
                let output = try await BorderToolService.render(source, percent: percent, color: borderColor)
                switch target {
                case let .board(project):
                    try addToBoard(output, project: project)
                case let .folder(folder):
                    let name = uniqueBorderFileName(base: source.name, fileExtension: output.fileExtension, taken: taken)
                    // .withoutOverwriting: a file that appeared since the listing still never gets replaced.
                    try output.data.write(to: folder.appendingPathComponent(name, isDirectory: false), options: .withoutOverwriting)
                    taken.insert(name.lowercased())
                }
            } catch {
                failedSources.append(source)
            }
        }
        isWorking = false
        guard failedSources.isEmpty else {
            // Keep only what failed, so the user sees which files to retry.
            sources = failedSources
            reportFailures(failedSources.count, "couldn't be bordered")
            return
        }
        dismiss()
    }

    private func resolveTarget() -> Target? {
        switch destination {
        case .board:
            return projects.first { $0.id == boardID }.map(Target.board)
        case .folder:
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Save"
            guard panel.runModal() == .OK, let folder = panel.url else { return nil }
            return .folder(folder)
        }
    }

    /// A button action, never mid-gesture, so writing the model here is safe.
    private func addToBoard(_ output: BorderedImage, project: Project) throws {
        let size = aspectFit(pixelWidth: output.pixelWidth, pixelHeight: output.pixelHeight, maxEdge: ImageImportService.maxDisplayEdge)
        let bounds = boardContentBounds(project.items.map {
            (center: CGPoint(x: $0.positionX, y: $0.positionY), size: CGSize(width: $0.width, height: $0.height))
        })
        try ImageImportService.insertImage(
            data: output.data,
            fileExtension: output.fileExtension,
            pixelWidth: output.pixelWidth,
            pixelHeight: output.pixelHeight,
            into: project,
            at: appendedImportCenter(contentBounds: bounds, size: size),
            context: modelContext
        )
    }

    private func reportFailures(_ count: Int, _ outcome: String) {
        guard count > 0 else { return }
        failureMessage = count == 1 ? "1 image \(outcome)." : "\(count) images \(outcome)."
        isShowingFailure = true
    }
}
```

- [ ] **Step 6: Run the UI test to verify it passes**

Run: `xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS' -only-testing:moodyUITests/BorderToolUITests`
Expected: PASS.

- [ ] **Step 7: Lint**

Run: `swiftformat . && swiftformat --lint . && swiftlint lint --strict`
Expected: no violations.

---

### Task 6: Docs, full verification and manual QA

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Document the tool in CLAUDE.md**

In `CLAUDE.md` § Architecture, add this paragraph after the **Import pipeline** paragraph:

```markdown
**Add Border tool** (`moody/Views/Border/`, `moody/Import/BorderRenderer.swift`, `BorderToolService.swift`). Tools ▸ Add Border… (⇧⌘B) toggles a `FocusedValues.showsBorderTool` binding published by `RootView`, which presents `BorderToolView` as a sheet, defaulting to the open board. Sources (dropped or chosen files) are read into memory when added. `BorderRenderer` is pure and `nonisolated`: it pads into a bitmap context that matches the source's color space and bit depth (sRGB fallback for indexed sources, or for grayscale with a colored border), copies the photo in at an integer offset with no interpolation, and re-encodes in the source's type with its metadata at lossy quality 1.0. Board output goes through `ImageImportService.insertImage`, placed right of existing content (`appendedImportCenter`). Folder output never overwrites (`uniqueBorderFileName` + `.withoutOverwriting`).
```

- [ ] **Step 2: Run the full test suite and lint**

Run:
```sh
swiftformat --lint .
swiftlint lint --strict
xcodebuild test -project moody.xcodeproj -scheme moody -destination 'platform=macOS'
```
Expected: no lint violations, and every test PASSES, including the existing import and storage suites, which cover the `importOne` refactor.

- [ ] **Step 3: Manual QA**

Run the app (`xcodebuild build …`, then launch, or ⌘R in Xcode):

1. Open a board that has photos. Press ⇧⌘B; the sheet opens with that board preselected.
2. From Finder, drag a JPEG, a PNG with transparency and an SVG onto the sheet. Drag one image from Safari. All 4 are listed, and the preview shows the first one.
3. Set 10% and pick a color. Click **Add to Board**. The 4 images appear in a row right of the existing photos, each with an even border of that color. The PNG is still transparent inside.
4. Reopen the sheet, add the same files, choose **Folder**, click **Save…** and pick a folder. Open the outputs in Preview. ⌘I shows the source size + 2 × border, the same color profile, and the EXIF/orientation intact. Repeat into the same folder: `… border 2.*` files appear and nothing is replaced.
5. Add a file, then delete it in Finder before applying (it still works, since bytes are loaded on add). Then rename a `.txt` to `.png` and add it: you see "1 image couldn't be bordered.", the others are saved, and only the bad file remains in the list.
6. With no boards at all, ⇧⌘B opens with **Folder** selected.
