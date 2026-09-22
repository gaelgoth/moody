//
//  ProjectListView.swift
//  moody
//
//  Sidebar: lists boards, and supports creating, renaming, and deleting
//  them. Deleting a project also cleans up its image files on disk, since
//  SwiftData's cascade delete only removes the database rows.
//

import SwiftData
import SwiftUI

struct ProjectListView: View {
    @Query(sort: \Project.createdAt) private var projects: [Project]
    @Environment(\.modelContext) private var modelContext
    @Binding var selection: Project?

    @State private var projectPendingRename: Project?
    @State private var renameText = ""
    @State private var projectPendingDelete: Project?

    var body: some View {
        List(selection: $selection) {
            ForEach(projects) { project in
                Text(project.name)
                    .tag(project)
                    .contextMenu {
                        Button("Rename…") {
                            renameText = project.name
                            projectPendingRename = project
                        }
                        Button("Delete", role: .destructive) {
                            projectPendingDelete = project
                        }
                    }
            }
        }
        .toolbar {
            ToolbarItem {
                Button(action: createProject) {
                    Label("New Board", systemImage: "plus")
                }
            }
        }
        .alert("Rename Board", isPresented: renameAlertBinding) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename", action: commitRename)
        }
        .confirmationDialog(
            "Delete “\(projectPendingDelete?.name ?? "")”?",
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: commitDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all images on this board.")
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { projectPendingRename != nil },
            set: { if !$0 { projectPendingRename = nil } }
        )
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { projectPendingDelete != nil },
            set: { if !$0 { projectPendingDelete = nil } }
        )
    }

    private func createProject() {
        let project = Project(name: "Untitled Board")
        modelContext.insert(project)
        try? modelContext.save()
        selection = project
    }

    private func commitRename() {
        guard let project = projectPendingRename else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            project.name = trimmed
            try? modelContext.save()
        }
        projectPendingRename = nil
    }

    private func commitDelete() {
        guard let project = projectPendingDelete else { return }
        let projectID = project.id
        if selection == project {
            selection = nil
        }
        modelContext.delete(project)
        try? modelContext.save()
        try? FileStorageService().deleteProjectDirectory(projectID: projectID)
        projectPendingDelete = nil
    }
}
