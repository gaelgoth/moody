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
    /// Multi-frame (GIF, HEICS): bordering frame 0 alone would silently drop the animation.
    case animatedImage
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
        guard CGImageSourceGetCount(source) == 1 else {
            throw BorderRenderError.animatedImage
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
