//
//  BoardDeletion.swift
//  moody
//
//  Deletes board items: the rows, plus each photo's stored file (cascade
//  delete only removes rows, as with a project's directory). Connectors go
//  with their endpoints by cascade. Toolbar / key action only, never
//  mid-gesture.
//

import Foundation
import OSLog
import SwiftData

private extension Logger {
    static let boardDeletion = Logger(subsystem: Bundle.main.bundleIdentifier ?? "moody", category: "BoardDeletion")
}

func deleteBoardItems(
    _ items: [BoardItem],
    context: ModelContext,
    storage: FileStorageService = FileStorageService(),
    cache: ImageCache = .shared
) {
    let deletedIDs = Set(items.map(\.id))
    // Containers that lose a photo (and aren't deleted themselves) close the gap.
    let shrinking = Set(items.compactMap(\.container)).filter { !deletedIDs.contains($0.id) }
    let files = items.compactMap { item -> (fileName: String, projectID: UUID)? in
        guard item.kind == .image, let projectID = item.project?.id else { return nil }
        return (item.fileName, projectID)
    }
    for item in items {
        context.delete(item)
    }
    for container in shrinking {
        relayout(container, children: container.stackedItems.filter { !deletedIDs.contains($0.id) })
    }
    // Save before touching disk: if the save fails the rows stay, and so must their files.
    do {
        try context.save()
    } catch {
        Logger.boardDeletion.error("Failed to delete board items: \(error.localizedDescription, privacy: .public)")
        return
    }
    for file in files {
        cache.evict(fileName: file.fileName)
        do {
            try storage.deleteFile(fileName: file.fileName, projectID: file.projectID)
        } catch {
            Logger.boardDeletion.error("Failed to delete image file: \(error.localizedDescription, privacy: .public)")
        }
    }
}
