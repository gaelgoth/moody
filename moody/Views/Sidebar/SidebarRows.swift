//
//  SidebarRows.swift
//  moody
//
//  Sidebar row views. `SidebarFolderRow` is recursive: a DisclosureGroup whose
//  content renders its subfolders (as further SidebarFolderRows) and boards.
//  Rows own no persistent state; renaming, drops and the appearance popover
//  are driven by SidebarView through `SidebarRowActions`.
//

import SwiftData
import SwiftUI

struct SidebarRowActions {
    var renamingTarget: SidebarSelection?
    var appearanceFolderID: Binding<UUID?>
    var commitRename: (SidebarSelection, String) -> Void
    var cancelRename: () -> Void
    /// Moves dropped rows into the given folder (nil = top level).
    var drop: ([SidebarItemReference], Folder?) -> Bool
}

struct SidebarFolderRow: View {
    @Bindable var folder: Folder
    let actions: SidebarRowActions

    @State private var isDropTargeted = false

    var body: some View {
        DisclosureGroup(isExpanded: $folder.isExpanded) {
            ForEach(sortedFolders(folder.subfolders)) { subfolder in
                SidebarFolderRow(folder: subfolder, actions: actions)
            }
            ForEach(sortedProjects(folder.projects)) { project in
                SidebarBoardRow(project: project, actions: actions)
            }
        } label: {
            label
        }
    }

    private var selection: SidebarSelection {
        .folder(folder.id)
    }

    private var label: some View {
        Label {
            if actions.renamingTarget == selection {
                InlineRenameField(
                    name: folder.name,
                    onCommit: { actions.commitRename(selection, $0) },
                    onCancel: actions.cancelRename
                )
            } else {
                Text(folder.name)
            }
        } icon: {
            Image(systemName: folder.resolvedIconName)
                .foregroundStyle(folder.resolvedColor.color)
        }
        .tag(selection)
        .draggable(SidebarItemReference(selection: selection))
        .dropDestination(for: SidebarItemReference.self) { references, _ in
            actions.drop(references, folder)
        } isTargeted: { isDropTargeted = $0 }
        .listRowBackground(dropHighlight)
        .popover(isPresented: appearanceBinding, arrowEdge: .trailing) {
            FolderAppearancePicker(iconName: Bindable(folder).iconName, colorName: Bindable(folder).colorName)
        }
    }

    @ViewBuilder private var dropHighlight: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.25))
                .padding(.horizontal, 6)
        }
    }

    private var appearanceBinding: Binding<Bool> {
        Binding(
            get: { actions.appearanceFolderID.wrappedValue == folder.id },
            set: {
                if !$0 {
                    actions.appearanceFolderID.wrappedValue = nil
                }
            }
        )
    }
}

struct SidebarBoardRow: View {
    let project: Project
    let actions: SidebarRowActions

    private var selection: SidebarSelection {
        .board(project.id)
    }

    var body: some View {
        Label {
            if actions.renamingTarget == selection {
                InlineRenameField(
                    name: project.name,
                    onCommit: { actions.commitRename(selection, $0) },
                    onCancel: actions.cancelRename
                )
            } else {
                Text(project.name)
            }
        } icon: {
            Image(systemName: "photo.on.rectangle.angled")
        }
        .badge(project.items.count)
        .tag(selection)
        .draggable(SidebarItemReference(selection: selection))
        // Dropping onto a board files the dropped rows next to it.
        .dropDestination(for: SidebarItemReference.self) { references, _ in
            _ = actions.drop(references, project.folder)
        }
    }
}
