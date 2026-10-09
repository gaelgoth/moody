//
//  RootView.swift
//  moody
//

import SwiftData
import SwiftUI

struct RootView: View {
    @State private var selection: SidebarSelection?
    @Query private var folders: [Folder]
    @Query private var projects: [Project]

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            detail
        }
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case let .board(id):
            if let project = projects.first(where: { $0.id == id }) {
                BoardView(project: project)
            } else {
                noSelection
            }
        case let .folder(id):
            if let folder = folders.first(where: { $0.id == id }) {
                FolderSummaryView(folder: folder)
            } else {
                noSelection
            }
        case nil:
            noSelection
        }
    }

    private var noSelection: some View {
        ContentUnavailableView(
            "No Board Selected",
            systemImage: "rectangle.dashed",
            description: Text("Choose a board from the sidebar, or create a new one.")
        )
    }
}

/// Detail placeholder shown when a folder (rather than a board) is selected.
private struct FolderSummaryView: View {
    let folder: Folder

    var body: some View {
        let boardCount = descendantProjects(of: folder).count
        ContentUnavailableView {
            Label {
                Text(folder.name)
            } icon: {
                Image(systemName: folder.resolvedIconName)
                    .foregroundStyle(folder.resolvedColor.color)
            }
        } description: {
            Text(boardCount == 1 ? "1 board" : "\(boardCount) boards")
        }
        .navigationTitle(folder.name)
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Folder.self, Project.self, BoardItem.self], inMemory: true)
}
