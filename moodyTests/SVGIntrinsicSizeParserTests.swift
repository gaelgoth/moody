//
//  SVGIntrinsicSizeParserTests.swift
//  moodyTests
//

import Testing
import Foundation
@testable import moody

struct SVGIntrinsicSizeParserTests {

    @Test func parsesSizeFromWidthAndHeightAttributes() {
        let svg = "<svg width=\"200\" height=\"100\" xmlns=\"http://www.w3.org/2000/svg\"></svg>"
        let size = SVGIntrinsicSizeParser.parse(Data(svg.utf8))
        #expect(size == CGSize(width: 200, height: 100))
    }

    @Test func parsesSizeFromViewBoxWhenWidthAndHeightAreMissing() {
        let svg = "<svg viewBox=\"0 0 300 150\" xmlns=\"http://www.w3.org/2000/svg\"></svg>"
        let size = SVGIntrinsicSizeParser.parse(Data(svg.utf8))
        #expect(size == CGSize(width: 300, height: 150))
    }

    @Test func prefersWidthAndHeightOverViewBoxWhenBothPresent() {
        let svg = "<svg width=\"50\" height=\"25\" viewBox=\"0 0 300 150\" xmlns=\"http://www.w3.org/2000/svg\"></svg>"
        let size = SVGIntrinsicSizeParser.parse(Data(svg.utf8))
        #expect(size == CGSize(width: 50, height: 25))
    }

    @Test func fallsBackToDefaultSquareWhenWidthHeightAreUnitlessPercentages() {
        let svg = "<svg width=\"100%\" height=\"100%\" xmlns=\"http://www.w3.org/2000/svg\"></svg>"
        let size = SVGIntrinsicSizeParser.parse(Data(svg.utf8))
        #expect(size == SVGIntrinsicSizeParser.fallbackSize)
    }

    @Test func fallsBackToDefaultSquareWhenNothingIsParsable() {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>"
        let size = SVGIntrinsicSizeParser.parse(Data(svg.utf8))
        #expect(size == SVGIntrinsicSizeParser.fallbackSize)
    }

    @Test func fallsBackToDefaultSquareForMalformedMarkup() {
        let svg = "not even xml"
        let size = SVGIntrinsicSizeParser.parse(Data(svg.utf8))
        #expect(size == SVGIntrinsicSizeParser.fallbackSize)
    }
}
