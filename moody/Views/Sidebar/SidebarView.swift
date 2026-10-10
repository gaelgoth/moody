//
//  SidebarView.swift
//  moody
//
//  Sidebar: a tree of folders and boards. Supports creating, inline renaming
//  (double-click or Return, via `contextMenu(forSelectionType:primaryAction:)`
//  — a TapGesture(count: 2) on a List row would delay/break single-click
//  selection), moving (drag and drop or the "Move to" menu), folder icon and
//  color, and deleting. Deleting also removes image files on disk, since
//  SwiftData's cascade delete only removes the database rows.
//

import SwiftData
import SwiftUI

struct SidebarView: View {
    @Query(sort: \Folder.createdAt) private var folders: [Folder]
    @Query(sort: \Project.createdAt) private var projects: [Project]
    @Environment(\.modelContext) private var modelContext
    @Binding var selection: SidebarSelection?

    @State private var renamingTarget: SidebarSelection?
    @State private var appearanceFolderID: UUID?
    @State private var pendingDelete: SidebarSelection?

    var body: some View {
        List(selection: $selection) {
            ForEach(sortedFolders(folders.filter { $0.parent == nil })) { folder in
                SidebarFolderRow(folder: folder, actions: rowActions)
            }
            ForEach(sortedProjects(projects.filter { $0.folder == nil })) { project in
                SidebarBoardRow(project: project, actions: rowActions)
            }
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: SidebarSelection.self) { targets in
            if let target = targets.first, targets.count == 1 {
                contextMenu(for: target)
            }
        } primaryAction: { targets in
            if let target = targets.first, targets.count == 1 {
                renamingTarget = target
            }
        }
        // Drops that no row claims (empty space below the rows) go to top level.
        .dropDestination(for: SidebarItemReference.self) { references, _ in
            _ = drop(references, into: nil)
        }
        .toolbar {
            // One toolbar item: two separate buttons overflow the narrow
            // sidebar toolbar and hide "New Board" behind the » menu.
            ToolbarItem {
                Menu {
                    Button("New Board", systemImage: "photo.on.rectangle.angled", action: createProject)
                    Button("New Folder", systemImage: "folder.badge.plus", action: createFolder)
                } label: {
                    Label("New", systemImage: "plus")
                }
                .help("New Board or Folder")
            }
        }
        .confirmationDialog(
            "Delete “\(pendingDeleteName)”?",
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: commitDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(pendingDeleteMessage)
        }
    }

    // MARK: Lookup

    private func folder(_ id: UUID) -> Folder? {
        folders.first { $0.id == id }
    }

    private func project(_ id: UUID) -> Project? {
        projects.first { $0.id == id }
    }

    /// Where new items go: the selected folder, or the selected board's folder.
    private var currentFolder: Folder? {
        switch selection {
        case let .folder(id): folder(id)
        case let .board(id): project(id)?.folder
        case nil: nil
        }
    }

    // MARK: Row actions

    private var rowActions: SidebarRowActions {
        SidebarRowActions(
            renamingTarget: renamingTarget,
            appearanceFolderID: $appearanceFolderID,
            commitRename: commitRename,
            cancelRename: { renamingTarget = nil },
            drop: { drop($0, into: $1) }
        )
    }

    private func commitRename(_ target: SidebarSelection, text: String) {
        defer { renamingTarget = nil }
        guard let name = renamedName(text) else { return }
        switch target {
        case let .folder(id): folder(id)?.name = name
        case let .board(id): project(id)?.name = name
        }
        try? modelContext.save()
    }

    private func drop(_ references: [SidebarItemReference], into target: Folder?) -> Bool {
        var movedAny = false
        for reference in references where move(reference, into: target, folders: folders, projects: projects) {
            movedAny = true
        }
        guard movedAny else { return false }
        target?.isExpanded = true
        try? modelContext.save()
        return true
    }

    // MARK: Context menu

    @ViewBuilder
    private func contextMenu(for target: SidebarSelection) -> some View {
        Button("Rename") { renamingTarget = target }
        if case let .folder(id) = target {
            Button("Change Icon & Color…") { appearanceFolderID = id }
            Divider()
            Button("New Folder Inside") { createFolder(in: folder(id)) }
            Button("New Board Inside") { createProject(in: folder(id)) }
        }
        Divider()
        moveMenu(for: target)
        Divider()
        Button("Delete…", role: .destructive) { pendingDelete = target }
    }

    @ViewBuilder
    private func moveMenu(for target: SidebarSelection) -> some View {
        let reference = SidebarItemReference(selection: target)
        let movingFolder = movingFolder(for: target)
        Menu("Move To") {
            Button("Top Level") { _ = drop([reference], into: nil) }
            Divider()
            ForEach(folderOutline(folders.filter { $0.parent == nil }), id: \.folder.id) { entry in
                Button {
                    _ = drop([reference], into: entry.folder)
                } label: {
                    Label(
                        String(repeating: "\u{2003}", count: entry.depth) + entry.folder.name,
                        systemImage: entry.folder.resolvedIconName
                    )
                }
                .disabled(movingFolder.map { !canMove($0, into: entry.folder) } ?? false)
            }
        }
    }

    private func movingFolder(for target: SidebarSelection) -> Folder? {
        guard case let .folder(id) = target else { return nil }
        return folder(id)
    }

    // MARK: Create

    private func createFolder() {
        createFolder(in: currentFolder)
    }

    private func createFolder(in parent: Folder?) {
        let siblings = folders.filter { $0.parent === parent }.map(\.name)
        let folder = Folder(name: uniqueName("Untitled Folder", among: siblings), parent: parent)
        modelContext.insert(folder)
        parent?.isExpanded = true
        try? modelContext.save()
        selection = .folder(folder.id)
        renamingTarget = .folder(folder.id)
    }

    private func createProject() {
        createProject(in: currentFolder)
    }

    private func createProject(in parent: Folder?) {
        let siblings = projects.filter { $0.folder === parent }.map(\.name)
        let project = Project(name: uniqueName("Untitled Board", among: siblings), folder: parent)
        modelContext.insert(project)
        parent?.isExpanded = true
        try? modelContext.save()
        selection = .board(project.id)
        renamingTarget = .board(project.id)
    }

    // MARK: Delete

    private var pendingDeleteName: String {
        switch pendingDelete {
        case let .folder(id): folder(id)?.name ?? ""
        case let .board(id): project(id)?.name ?? ""
        case nil: ""
        }
    }

    private var pendingDeleteMessage: String {
        guard case let .folder(id) = pendingDelete, let folder = folder(id) else {
            return "This permanently deletes all images on this board."
        }
        let boardCount = descendantProjects(of: folder).count
        if boardCount == 0 {
            return "This deletes the folder and any folders inside it."
        }
        let boards = boardCount == 1 ? "1 board" : "\(boardCount) boards"
        return "This permanently deletes the folder, \(boards) inside it, and all their images."
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: {
                if !$0 {
                    pendingDelete = nil
                }
            }
        )
    }

    private func commitDelete() {
        defer { pendingDelete = nil }
        let removedProjectIDs: [UUID]
        switch pendingDelete {
        case let .folder(id):
            guard let folder = folder(id) else { return }
            removedProjectIDs = descendantProjects(of: folder).map(\.id)
            if let selection, selectionsRemoved(byDeleting: folder).contains(selection) {
                self.selection = nil
            }
            modelContext.delete(folder)
        case let .board(id):
            guard let project = project(id) else { return }
            removedProjectIDs = [id]
            if selection == .board(id) {
                selection = nil
            }
            modelContext.delete(project)
        case nil:
            return
        }
        try? modelContext.save()
        let storage = FileStorageService()
        for projectID in removedProjectIDs {
            try? storage.deleteProjectDirectory(projectID: projectID)
        }
    }
}

#Preview {
    let container = try! ModelContainer( // swiftlint:disable:this force_try
        for: Folder.self, Project.self, BoardItem.self, BoardConnector.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let inspiration = Folder(name: "Inspiration", iconName: "sparkles", colorName: "purple")
    let interiors = Folder(name: "Interiors", iconName: "house", colorName: "orange", parent: inspiration)
    container.mainContext.insert(inspiration)
    container.mainContext.insert(interiors)
    container.mainContext.insert(Project(name: "Living room", folder: interiors))
    container.mainContext.insert(Project(name: "Palette ideas", folder: inspiration))
    container.mainContext.insert(Project(name: "Loose board"))
    return NavigationSplitView {
        SidebarView(selection: .constant(nil))
    } detail: {
        Text("Detail")
    }
    .modelContainer(container)
}
