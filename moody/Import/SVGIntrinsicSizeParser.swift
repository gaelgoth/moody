//
//  SVGIntrinsicSizeParser.swift
//  moody
//
//  Extracts the intrinsic size of an SVG's root element without a full XML
//  parser, so we know what resolution to rasterize it at on import.
//

import Foundation

enum SVGIntrinsicSizeParser {
    static let fallbackSize = CGSize(width: 512, height: 512)

    static func parse(_ data: Data) -> CGSize {
        guard let text = String(data: data, encoding: .utf8),
              let svgTag = firstSVGOpeningTag(in: text)
        else {
            return fallbackSize
        }

        if let width = numericAttribute("width", in: svgTag),
           let height = numericAttribute("height", in: svgTag) {
            return CGSize(width: width, height: height)
        }

        if let viewBox = attributeValue("viewBox", in: svgTag) {
            let components = viewBox
                .split(whereSeparator: { $0 == " " || $0 == "," })
                .compactMap { Double($0) }
            if components.count == 4 {
                return CGSize(width: components[2], height: components[3])
            }
        }

        return fallbackSize
    }

    private static func firstSVGOpeningTag(in text: String) -> String? {
        guard let start = text.range(of: "<svg") else { return nil }
        guard let end = text.range(of: ">", range: start.upperBound ..< text.endIndex) else { return nil }
        return String(text[start.lowerBound ..< end.upperBound])
    }

    private static func attributeValue(_ name: String, in tag: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\\b\(name)\\s*=\\s*\"([^\"]*)\"") else {
            return nil
        }
        let nsTag = tag as NSString
        guard let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: nsTag.length)) else {
            return nil
        }
        return nsTag.substring(with: match.range(at: 1))
    }

    /// Only accepts a bare number (SVG's default user-unit). Rejects
    /// percentages and other units, which have no fixed pixel size.
    private static func numericAttribute(_ name: String, in tag: String) -> Double? {
        guard let raw = attributeValue(name, in: tag) else { return nil }
        return Double(raw)
    }
}
