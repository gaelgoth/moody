//
//  FileStorageService.swift
//  moody
//
//  Owns where a project's imported image files live on disk, under:
//  <rootDirectory>/Projects/<project-id>/images/<file-name>
//

import Foundation

nonisolated struct FileStorageService {
    private let rootDirectory: URL

    /// Defaults to the app's Application Support directory. Tests inject a
    /// temporary root instead so file operations don't touch real user data.
    init(rootDirectory: URL = FileStorageService.defaultRootDirectory()) {
        self.rootDirectory = rootDirectory
    }

    private static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Moody", isDirectory: true)
    }

    func imagesDirectory(projectID: UUID) -> URL {
        rootDirectory
            .appendingPathComponent("Projects", isDirectory: true)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent("images", isDirectory: true)
    }

    func fileURL(fileName: String, projectID: UUID) -> URL {
        imagesDirectory(projectID: projectID).appendingPathComponent(fileName, isDirectory: false)
    }

    func write(data: Data, fileName: String, projectID: UUID) throws {
        let directory = imagesDirectory(projectID: projectID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(fileName: fileName, projectID: projectID), options: .atomic)
    }

    func deleteFile(fileName: String, projectID: UUID) throws {
        try FileManager.default.removeItem(at: fileURL(fileName: fileName, projectID: projectID))
    }

    func deleteProjectDirectory(projectID: UUID) throws {
        let directory = imagesDirectory(projectID: projectID).deletingLastPathComponent()
        try FileManager.default.removeItem(at: directory)
    }

    /// Copies each stored file into `folder`, replacing any file of the same
    /// name. Returns the names that could not be copied; one failure doesn't
    /// stop the rest.
    func exportFiles(fileNames: [String], projectID: UUID, to folder: URL) -> [String] {
        let fileManager = FileManager.default
        var failed: [String] = []
        for fileName in fileNames {
            let source = fileURL(fileName: fileName, projectID: projectID)
            let destination = folder.appendingPathComponent(fileName, isDirectory: false)
            // Check the source first so a missing file never deletes the user's earlier copy.
            guard fileManager.fileExists(atPath: source.path) else {
                failed.append(fileName)
                continue
            }
            // Exporting into the storage folder itself: already there; removing would delete the board's file.
            guard source.standardizedFileURL != destination.standardizedFileURL else { continue }
            do {
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: source, to: destination)
            } catch {
                failed.append(fileName)
            }
        }
        return failed
    }
}
