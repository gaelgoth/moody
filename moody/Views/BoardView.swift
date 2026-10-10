//
//  BoardView.swift
//  moody
//

import AppKit
import SwiftData
import SwiftUI

struct BoardView: View {
    @Bindable var project: Project
    @Query private var items: [BoardItem]
    @Environment(\.modelContext) private var modelContext
    @State private var zoomScale: CGFloat = 1
    /// Board-space point under the cursor, kept up to date by hover so
    /// pinch-zoom is anchored at the cursor. nil until the mouse first moves
    /// over the board (zoom then anchors at the viewport center).
    @State private var zoomAnchor: CGPoint?
    @State private var canvasController = BoardCanvasController()
    /// Lives here (not in the canvas content) so the toolbar can switch to
    /// selection actions. Ephemeral; resets per board.
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var failedDownloadCount = 0
    @State private var isShowingDownloadFailure = false

    init(project: Project) {
        _project = Bindable(project)
        let projectID = project.id
        _items = Query(
            filter: #Predicate<BoardItem> { $0.project?.id == projectID },
            sort: \BoardItem.zIndex
        )
    }

    /// Resolved against `items` so ids of deleted items are ignored.
    private var selectedItems: [BoardItem] {
        items.filter { selectedItemIDs.contains($0.id) }
    }

    var body: some View {
        BoardCanvasView(
            project: project,
            items: items,
            zoomScale: $zoomScale,
            zoomAnchor: $zoomAnchor,
            selectedItemIDs: $selectedItemIDs,
            controller: canvasController
        )
        .overlay(alignment: .bottomTrailing) {
            Text(zoomScale, format: .percent.precision(.fractionLength(0)))
                .font(.caption)
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
                .padding(12)
                .allowsHitTesting(false)
        }
        .navigationTitle(project.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Zoom to Fit", systemImage: "arrow.up.left.and.arrow.down.right") {
                    canvasController.zoomToFit()
                }
                .keyboardShortcut("0", modifiers: .command)
                .help("Zoom to Fit (⌘0)")
                .disabled(items.isEmpty)
            }
            if selectedItems.isEmpty {
                ToolbarItemGroup(placement: .primaryAction) {
                    Toggle("Grid", systemImage: "grid", isOn: $project.showsGrid)
                        .help("Grid")
                    Button(
                        project.usesDarkBackground ? "Light Background" : "Dark Background",
                        systemImage: project.usesDarkBackground ? "sun.max" : "moon"
                    ) {
                        project.usesDarkBackground.toggle()
                    }
                    .help(project.usesDarkBackground ? "Light Background" : "Dark Background")
                    Button("Download All", systemImage: "square.and.arrow.down") {
                        download(items)
                    }
                    .help("Download All")
                    .disabled(items.isEmpty)
                }
            } else {
                ToolbarItemGroup(placement: .primaryAction) {
                    ForEach(BoardAlignment.allCases, id: \.self) { alignment in
                        Button(alignment.title, systemImage: alignment.systemImage) {
                            align(alignment)
                        }
                        .help(alignment.title)
                        .disabled(selectedItems.count < 2)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Download Selected", systemImage: "square.and.arrow.down") {
                        download(selectedItems)
                    }
                    .help(selectedItems.count == 1 ? "Download Image" : "Download \(selectedItems.count) Images")
                }
            }
        }
        .onChange(of: project.showsGrid) { try? modelContext.save() }
        .onChange(of: project.usesDarkBackground) { try? modelContext.save() }
        .alert(
            failedDownloadCount == 1 ? "1 image couldn't be downloaded." : "\(failedDownloadCount) images couldn't be downloaded.",
            isPresented: $isShowingDownloadFailure
        ) {
            Button("OK") {}
        }
    }

    /// A toolbar click, never mid-gesture, so writing the model here is safe.
    private func align(_ alignment: BoardAlignment) {
        let targets = selectedItems
        let centers = alignedCenters(targets.map {
            (id: $0.id, center: CGPoint(x: $0.positionX, y: $0.positionY), size: CGSize(width: $0.width, height: $0.height))
        }, to: alignment)
        for item in targets {
            guard let center = centers[item.id] else { continue }
            item.positionX = center.x
            item.positionY = center.y
        }
        try? modelContext.save()
    }

    private func download(_ targets: [BoardItem]) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Download"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        // shortcut: copies synchronously on the main thread (APFS clones are near-instant); move off-main if large boards stall.
        let failed = FileStorageService().exportFiles(fileNames: targets.map(\.fileName), projectID: project.id, to: folder)
        failedDownloadCount = failed.count
        isShowingDownloadFailure = !failed.isEmpty
    }
}
