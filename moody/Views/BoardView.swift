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
    /// Unfiltered (a two-hop `from?.project?.id` predicate is unreliable) and
    /// narrowed in `connectors`. A query, not `items.flatMap(\.outgoingConnectors)`:
    /// inverse-only relationship changes don't reliably re-render the view.
    @Query private var allConnectors: [BoardConnector]
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
    /// The note or container whose text is being edited. Ephemeral.
    @State private var editingItemID: UUID?
    /// The clicked connector line. Ephemeral, and never set together with selectedItemIDs.
    @State private var selectedConnectorID: UUID?
    @State private var failedDownloadCount = 0
    @State private var isShowingDownloadFailure = false
    @State private var isConfirmingDelete = false

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

    private var connectors: [BoardConnector] {
        allConnectors.filter { $0.from?.project?.id == project.id }
    }

    /// The link between exactly two selected items, if they're linked.
    private var selectedPairConnector: BoardConnector? {
        guard selectedItems.count == 2 else { return nil }
        return connector(between: selectedItems[0].id, and: selectedItems[1].id, in: connectors)
    }

    private var selectedImages: [BoardItem] {
        selectedItems.filter { $0.kind == .image }
    }

    var body: some View {
        BoardCanvasView(
            project: project,
            items: items,
            connectors: connectors,
            zoomScale: $zoomScale,
            zoomAnchor: $zoomAnchor,
            selectedItemIDs: $selectedItemIDs,
            editingItemID: $editingItemID,
            selectedConnectorID: $selectedConnectorID,
            controller: canvasController,
            onDeleteKey: handleDeleteKey,
            itemMenuActions: BoardItemMenuActions(
                select: { ids in
                    selectedItemIDs = ids
                    selectedConnectorID = nil
                },
                connect: toggleConnection,
                group: groupSelection,
                removeFromContainer: removeSelectionFromContainer,
                align: align,
                download: { download(selectedItems) },
                delete: { _ = handleDeleteKey() }
            )
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
                // One menu, like the sidebar's "New": separate buttons overflow the toolbar.
                Menu {
                    Button("Note", systemImage: "note.text", action: addNote)
                    Button("Row Container", systemImage: "rectangle.split.3x1") { addContainer(.row) }
                    Button("Column Container", systemImage: "rectangle.split.1x3") { addContainer(.column) }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .help("Add Note or Container")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Zoom to Fit", systemImage: "arrow.up.left.and.arrow.down.right") {
                    canvasController.zoomToFit()
                }
                .keyboardShortcut("0", modifiers: .command)
                .help("Zoom to Fit (⌘0)")
                .disabled(items.isEmpty)
            }
            if selectedItems.isEmpty, selectedConnectorID != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Unlink", systemImage: "scissors", action: unlinkSelectedConnector)
                        .help("Unlink (⌫)")
                }
            } else if selectedItems.isEmpty {
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
                    .disabled(!items.contains { $0.kind == .image })
                }
            } else {
                ToolbarItemGroup(placement: .primaryAction) {
                    ForEach(BoardAlignment.allCases, id: \.self) { alignment in
                        Button(alignment.title, systemImage: alignment.systemImage) {
                            align(alignment)
                        }
                        .help(alignment.title)
                        .disabled(selectedItems.count(where: { $0.container == nil }) < 2)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Download Selected", systemImage: "square.and.arrow.down") {
                        download(selectedItems)
                    }
                    .help(selectedImages.count == 1 ? "Download Image" : "Download \(selectedImages.count) Images")
                    .disabled(selectedImages.isEmpty)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(
                        selectedPairConnector == nil ? "Connect" : "Unlink",
                        systemImage: selectedPairConnector == nil ? "link" : "scissors",
                        action: toggleConnection
                    )
                    .help(selectedPairConnector == nil ? "Connect the Two Selected Items" : "Unlink the Two Selected Items")
                    .disabled(selectedItems.count != 2)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Delete", systemImage: "trash") {
                        _ = handleDeleteKey()
                    }
                    .help("Delete (⌫)")
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
        .alert(
            selectedItems.count == 1 ? "Delete 1 item?" : "Delete \(selectedItems.count) items?",
            isPresented: $isConfirmingDelete
        ) {
            Button("Delete", role: .destructive, action: deleteSelection)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Photos are removed from the board and from disk. This can't be undone.")
        }
    }

    /// ⌫ and the toolbar Delete button. Photos lose their file with no undo,
    /// so only those ask first.
    private func handleDeleteKey() -> Bool {
        if selectedConnectorID != nil {
            unlinkSelectedConnector()
            return true
        }
        guard !selectedItems.isEmpty else { return false }
        if selectedImages.isEmpty {
            deleteSelection()
        } else {
            isConfirmingDelete = true
        }
        return true
    }

    /// Toolbar click, never mid-gesture.
    private func toggleConnection() {
        guard selectedItems.count == 2 else { return }
        if let existing = selectedPairConnector {
            modelContext.delete(existing)
        } else {
            modelContext.insert(BoardConnector(from: selectedItems[0], to: selectedItems[1]))
        }
        try? modelContext.save()
    }

    private func unlinkSelectedConnector() {
        guard let id = selectedConnectorID, let selected = connectors.first(where: { $0.id == id }) else { return }
        selectedConnectorID = nil
        modelContext.delete(selected)
        try? modelContext.save()
    }

    private func deleteSelection() {
        let targets = selectedItems
        selectedItemIDs = []
        deleteBoardItems(targets, context: modelContext)
    }

    private func addNote() {
        let note = BoardItem.note(
            at: canvasController.visibleCenter(),
            zIndex: nextZIndex(existing: items.map(\.zIndex)),
            project: project
        )
        modelContext.insert(note)
        try? modelContext.save()
        selectedItemIDs = [note.id]
        selectedConnectorID = nil
        editingItemID = note.id
    }

    private func addContainer(_ axis: StackAxis) {
        let container = BoardItem.container(
            axis: axis,
            at: canvasController.visibleCenter(),
            zIndex: nextZIndex(existing: items.map(\.zIndex)),
            project: project
        )
        modelContext.insert(container)
        try? modelContext.save()
        selectedItemIDs = [container.id]
        selectedConnectorID = nil
        editingItemID = container.id
    }

    /// Menu click, never mid-gesture. Only photos stack; other selected items stay put.
    private func groupSelection(_ axis: StackAxis) {
        let photos = selectedImages
        guard !photos.isEmpty else { return }
        let container = BoardItem.container(
            axis: axis,
            at: .zero,
            zIndex: nextZIndex(existing: items.map(\.zIndex)),
            project: project
        )
        modelContext.insert(container)
        stackIntoNewContainer(photos, container: container, allZIndices: items.map(\.zIndex) + [container.zIndex])
        try? modelContext.save()
        selectedItemIDs = [container.id]
    }

    private func removeSelectionFromContainer() {
        removeFromStack(selectedItems.filter { $0.container != nil })
        try? modelContext.save()
    }

    /// A toolbar click, never mid-gesture, so writing the model here is safe.
    private func align(_ alignment: BoardAlignment) {
        // Stacked photos follow their container; aligning them alone would be undone by relayout.
        let targets = selectedItems.filter { $0.container == nil }
        let centers = alignedCenters(targets.map {
            (id: $0.id, center: CGPoint(x: $0.positionX, y: $0.positionY), size: CGSize(width: $0.width, height: $0.height))
        }, to: alignment)
        for item in targets {
            guard let center = centers[item.id] else { continue }
            item.positionX = center.x
            item.positionY = center.y
        }
        for container in targets where container.kind == .container {
            relayout(container)
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
        let failed = FileStorageService().exportFiles(
            fileNames: targets.filter { $0.kind == .image }.map(\.fileName),
            projectID: project.id,
            to: folder
        )
        failedDownloadCount = failed.count
        isShowingDownloadFailure = !failed.isEmpty
    }
}
