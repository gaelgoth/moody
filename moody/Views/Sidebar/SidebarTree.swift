//
//  SidebarTree.swift
//  moody
//
//  Pure tree helpers for the sidebar: ordering, descendant lookup, cycle-safe
//  moves, and naming. Kept out of the views so they can be unit tested.
//

import Foundation

/// Folders in Finder-like natural name order ("Folder 2" before "Folder 10").
func sortedFolders(_ folders: [Folder]) -> [Folder] {
    folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}

/// Boards in Finder-like natural name order.
func sortedProjects(_ projects: [Project]) -> [Project] {
    projects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}

/// Every board inside `folder`, at any depth. Used to delete image
/// directories before a folder's cascade delete removes the rows.
func descendantProjects(of folder: Folder) -> [Project] {
    folder.projects + folder.subfolders.flatMap { descendantProjects(of: $0) }
}

/// Whether `folder` may become a child of `target` (nil = top level).
/// Rejects moving a folder into itself or into one of its descendants.
func canMove(_ folder: Folder, into target: Folder?) -> Bool {
    var ancestor = target
    while let current = ancestor {
        if current === folder {
            return false
        }
        ancestor = current.parent
    }
    return true
}

@discardableResult
func move(_ folder: Folder, into target: Folder?) -> Bool {
    guard canMove(folder, into: target) else { return false }
    if folder.parent !== target {
        folder.parent = target
    }
    return true
}

@discardableResult
func move(_ project: Project, into target: Folder?) -> Bool {
    if project.folder !== target {
        project.folder = target
    }
    return true
}

/// Resolves a drag payload against the known models and moves it.
/// Returns false if the item no longer exists or the move would create a cycle.
@discardableResult
func move(_ reference: SidebarItemReference, into target: Folder?, folders: [Folder], projects: [Project]) -> Bool {
    switch reference.selection {
    case let .folder(id):
        guard let folder = folders.first(where: { $0.id == id }) else { return false }
        return move(folder, into: target)
    case let .board(id):
        guard let project = projects.first(where: { $0.id == id }) else { return false }
        return move(project, into: target)
    }
}

/// `base`, or `base N` with the first N ≥ 2 not already taken.
func uniqueName(_ base: String, among existingNames: [String]) -> String {
    let taken = Set(existingNames)
    guard taken.contains(base) else { return base }
    var number = 2
    while taken.contains("\(base) \(number)") {
        number += 1
    }
    return "\(base) \(number)"
}

/// The committed form of an inline rename, or nil if it should be discarded.
func renamedName(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

/// Every selection that disappears when `folder` is deleted: the folder
/// itself plus all nested folders and boards.
func selectionsRemoved(byDeleting folder: Folder) -> Set<SidebarSelection> {
    var removed: Set<SidebarSelection> = [.folder(folder.id)]
    removed.formUnion(folder.projects.map { .board($0.id) })
    for subfolder in folder.subfolders {
        removed.formUnion(selectionsRemoved(byDeleting: subfolder))
    }
    return removed
}

/// Folders in depth-first display order with their nesting depth, for
/// building flat menus (e.g. "Move to").
func folderOutline(_ folders: [Folder], depth: Int = 0) -> [(folder: Folder, depth: Int)] {
    sortedFolders(folders).flatMap { folder in
        [(folder, depth)] + folderOutline(folder.subfolders, depth: depth + 1)
    }
}
