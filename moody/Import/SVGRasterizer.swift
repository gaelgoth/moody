//
//  SVGRasterizer.swift
//  moody
//
//  Rasterizes SVG data to PNG bytes via a short-lived, offscreen WKWebView,
//  since SwiftUI/AppKit have no native SVG renderer. Manual QA only — see
//  the project plan for why this isn't unit tested.
//

import AppKit
import WebKit

enum SVGRasterizationError: Error {
    case navigationFailed(Error)
    case snapshotFailed(Error)
    case snapshotProducedNoImage
    case pngEncodingFailed
}

@MainActor
final class SVGRasterizer: NSObject, WKNavigationDelegate {
    /// Renders SVG data to PNG bytes at a resolution derived from its intrinsic
    /// aspect ratio, capped so the long edge is at most `maxEdge` pixels.
    static func rasterize(svgData: Data, maxEdge: Double = 2048) async throws -> (pngData: Data, pixelWidth: Int, pixelHeight: Int) {
        let intrinsicSize = SVGIntrinsicSizeParser.parse(svgData)
        let pixelSize = aspectFit(
            pixelWidth: max(Int(intrinsicSize.width), 1),
            pixelHeight: max(Int(intrinsicSize.height), 1),
            maxEdge: maxEdge
        )

        let webView = WKWebView(frame: CGRect(origin: .zero, size: pixelSize))
        // Undocumented but long-standing KVC key to disable WKWebView's opaque
        // white page background — there's no public API for true page
        // transparency, and without this SVGs with transparent backgrounds
        // would rasterize onto solid white.
        webView.setValue(false, forKey: "drawsBackground")

        let rasterizer = SVGRasterizer()
        webView.navigationDelegate = rasterizer

        try await rasterizer.load(svgData, in: webView)
        let image = try await rasterizer.snapshot(of: webView)

        guard let pngData = image.pngData() else {
            throw SVGRasterizationError.pngEncodingFailed
        }
        return (pngData, Int(pixelSize.width), Int(pixelSize.height))
    }

    private var loadContinuation: CheckedContinuation<Void, Error>?

    private func load(_ svgData: Data, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            loadContinuation = continuation
            webView.load(svgData, mimeType: "image/svg+xml", characterEncodingName: "UTF-8", baseURL: URL(string: "about:blank")!)
        }
    }

    private func snapshot(of webView: WKWebView) async throws -> NSImage {
        try await withCheckedThrowingContinuation { continuation in
            let configuration = WKSnapshotConfiguration()
            configuration.rect = webView.bounds
            webView.takeSnapshot(with: configuration) { image, error in
                if let error {
                    continuation.resume(throwing: SVGRasterizationError.snapshotFailed(error))
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: SVGRasterizationError.snapshotProducedNoImage)
                }
            }
        }
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: SVGRasterizationError.navigationFailed(error))
        loadContinuation = nil
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: SVGRasterizationError.navigationFailed(error))
        loadContinuation = nil
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
