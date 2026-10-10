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
        try BorderSource(
            name: url.deletingPathExtension().lastPathComponent,
            data: Data(contentsOf: url),
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
