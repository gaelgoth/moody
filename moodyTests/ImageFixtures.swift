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
