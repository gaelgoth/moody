//
//  RootView.swift
//  moody
//

import SwiftData
import SwiftUI

struct RootView: View {
    @State private var selectedProject: Project?

    var body: some View {
        NavigationSplitView {
            ProjectListView(selection: $selectedProject)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            if let selectedProject {
                BoardView(project: selectedProject)
            } else {
                ContentUnavailableView(
                    "No Board Selected",
                    systemImage: "rectangle.dashed",
                    description: Text("Choose a board from the sidebar, or create a new one.")
                )
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Project.self, BoardItem.self], inMemory: true)
}
