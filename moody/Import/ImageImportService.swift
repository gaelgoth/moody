//
//  ImageImportService.swift
//  moody
//
//  Turns dropped NSItemProviders into persisted BoardItems: reads the file
//  data, rasterizes SVGs, decodes natural pixel size, writes to local
//  storage, and inserts the model — per item, so one bad file in a batch
//  doesn't abort the rest of the drop.
//

import AppKit
import ImageIO
import OSLog
import SwiftData
import UniformTypeIdentifiers

enum ImageImportError: Error {
    case noFileRepresentation
    case undecodableImage
}

private extension Logger {
    static let imageImport = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "moody",
        category: "ImageImport"
    )
}

enum ImageImportService {
    /// Default on-canvas display size cap (points, long edge).
    private static let maxDisplayEdge: Double = 320

    @MainActor
    static func importDroppedItems(
        _ providers: [NSItemProvider],
        into project: Project,
        at dropLocation: CGPoint,
        context: ModelContext,
        storage: FileStorageService = FileStorageService()
    ) async {
        var index = 0
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { continue }
            let position = cascadePosition(base: dropLocation, index: index)
            do {
                try await importOne(provider, into: project, at: position, context: context, storage: storage)
                index += 1
            } catch {
                Logger.imageImport.error("Failed to import dropped item: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @MainActor
    private static func importOne(
        _ provider: NSItemProvider,
        into project: Project,
        at position: CGPoint,
        context: ModelContext,
        storage: FileStorageService
    ) async throws {
        let (data, contentType) = try await loadFileRepresentation(provider)

        let finalData: Data
        let fileExtension: String
        let pixelWidth: Int
        let pixelHeight: Int

        if contentType.conforms(to: .svg) {
            let rasterized = try await SVGRasterizer.rasterize(svgData: data)
            finalData = rasterized.pngData
            fileExtension = "png"
            pixelWidth = rasterized.pixelWidth
            pixelHeight = rasterized.pixelHeight
        } else {
            finalData = data
            fileExtension = contentType.preferredFilenameExtension ?? "img"
            let size = try decodePixelSize(from: data)
            pixelWidth = size.width
            pixelHeight = size.height
        }

        let itemID = UUID()
        let fileName = "\(itemID.uuidString).\(fileExtension)"
        try storage.write(data: finalData, fileName: fileName, projectID: project.id)

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

    /// Reads the dropped item's bytes synchronously inside NSItemProvider's
    /// completion handler — the temp file URL it hands back is only
    /// guaranteed valid there, not after further async hops.
    private static func loadFileRepresentation(_ provider: NSItemProvider) async throws -> (data: Data, contentType: UTType) {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: ImageImportError.noFileRepresentation)
                    return
                }
                do {
                    let data = try Data(contentsOf: url)
                    let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
                        ?? UTType(filenameExtension: url.pathExtension)
                        ?? .image
                    continuation.resume(returning: (data, contentType))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func decodePixelSize(from data: Data) throws -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            throw ImageImportError.undecodableImage
        }
        return (width, height)
    }
}
