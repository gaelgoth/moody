//
//  ImageCache.swift
//  moody
//
//  Avoids re-decoding an item's image from disk on every board re-render
//  (e.g. during a drag). Evicted automatically by AppKit under memory
//  pressure — no manual sizing needed.
//

import AppKit

final class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, NSImage>()
    private let storage: FileStorageService

    init(storage: FileStorageService = FileStorageService()) {
        self.storage = storage
    }

    func image(for item: BoardItem) -> NSImage? {
        guard let projectID = item.project?.id else { return nil }
        let key = item.fileName as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let url = storage.fileURL(fileName: item.fileName, projectID: projectID)
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
