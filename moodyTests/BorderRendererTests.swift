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
        #expect(try isClose(ImageFixtures.pixel(output.data, x: 2, y: 2), white))
        #expect(try isClose(ImageFixtures.pixel(output.data, x: 60, y: 35), red))
    }

    @Test func sixteenBitPNGStaysSixteenBit() throws {
        let data = try ImageFixtures.make(bitsPerComponent: 16, fill: ImageFixtures.red)
        #expect(try ImageFixtures.decoded(data).bitsPerComponent == 16) // the fixture really is 16-bit
        let output = try BorderRenderer.addBorder(to: data, percent: 5, color: ImageFixtures.white)
        #expect(try ImageFixtures.decoded(output.data).bitsPerComponent == 16)
    }

    @Test func colorProfileIsPreserved() throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let data = try ImageFixtures.make(space: p3, fill: CGColor(colorSpace: p3, components: [1, 0, 0, 1]))
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

    @Test func animatedImageIsRejectedRatherThanFlattened() throws {
        // A 2-frame GIF: bordering only frame 0 would silently drop the animation.
        let frame = try ImageFixtures.decoded(ImageFixtures.make(fill: ImageFixtures.red))
        let gif = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(gif, UTType.gif.identifier as CFString, 2, nil))
        CGImageDestinationAddImage(destination, frame, nil)
        CGImageDestinationAddImage(destination, frame, nil)
        #expect(CGImageDestinationFinalize(destination))

        #expect(throws: BorderRenderError.animatedImage) {
            try BorderRenderer.addBorder(to: gif as Data, percent: 5, color: ImageFixtures.white)
        }
    }

    @Test func undecodableDataThrows() {
        #expect(throws: BorderRenderError.undecodableImage) {
            try BorderRenderer.addBorder(to: Data("not an image".utf8), percent: 5, color: ImageFixtures.white)
        }
    }
}
