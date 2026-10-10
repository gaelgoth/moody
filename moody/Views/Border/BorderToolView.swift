//
//  BorderToolView.swift
//  moody
//
//  Tools ▸ Add Border…: images dropped on the sheet or chosen from disk get a
//  border (percent of the long edge, any opaque color) and go to a board or a
//  folder. Pixels, format and quality are handled by BorderRenderer.
//

import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BorderToolView: View {
    private enum Destination: Hashable {
        case board
        case folder
    }

    private enum Target {
        case board(Project)
        case folder(URL)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.self) private var environment
    @Query(sort: \Project.name) private var projects: [Project]
    @State private var sources: [BorderSource] = []
    @State private var preview: NSImage?
    @State private var percent: Double = 5
    @State private var color: Color = .white
    @State private var destination: Destination = .board
    @State private var boardID: UUID?
    @State private var isDropTargeted = false
    @State private var isWorking = false
    @State private var failureMessage = ""
    @State private var isShowingFailure = false

    init(defaultBoardID: UUID?) {
        _boardID = State(initialValue: defaultBoardID)
    }

    private var canApply: Bool {
        !sources.isEmpty && !isWorking && (destination == .folder || boardID != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Border")
                .font(.headline)
            dropZone
                .disabled(isWorking)
            Form {
                LabeledContent("Border") {
                    HStack {
                        Slider(value: $percent, in: 0 ... 50)
                        TextField("Border", value: $percent, format: .number.precision(.fractionLength(0 ... 1)))
                            .labelsHidden()
                            .frame(width: 48)
                        Text("%")
                    }
                }
                ColorPicker("Color", selection: $color, supportsOpacity: false)
                Picker("Destination", selection: $destination) {
                    Text("Board").tag(Destination.board)
                    Text("Folder").tag(Destination.folder)
                }
                .pickerStyle(.segmented)
                if destination == .board {
                    Picker("Board", selection: $boardID) {
                        ForEach(projects) { project in
                            Text(project.name).tag(Optional(project.id))
                        }
                    }
                }
            }
            .disabled(isWorking)
            HStack {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isWorking)
                Button(destination == .board ? "Add to Board" : "Save…") {
                    Task { await apply() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canApply)
            }
        }
        .padding(20)
        .frame(width: 460)
        .interactiveDismissDisabled(isWorking)
        .onDrop(of: [.image], isTargeted: $isDropTargeted) { providers in
            // Mid-batch the list is about to be replaced or dismissed; a late drop would vanish.
            guard !isWorking else { return false }
            Task { await add(providers) }
            return true
        }
        .onAppear {
            if boardID == nil {
                boardID = projects.first?.id
            }
            if projects.isEmpty {
                destination = .folder
            }
        }
        .onChange(of: percent) {
            percent = min(max(percent, 0), 50)
        }
        .onChange(of: sources.first?.id) {
            // Decoded once per first-image change, not on every render.
            preview = sources.first.flatMap { NSImage(data: $0.data) }
        }
        .alert(failureMessage, isPresented: $isShowingFailure) {
            Button("OK") {}
        }
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            if let preview {
                let fit = aspectFit(pixelWidth: Int(preview.size.width), pixelHeight: Int(preview.size.height), maxEdge: 160)
                // Display only: the padding mirrors the percent of the long edge.
                Image(nsImage: preview)
                    .resizable()
                    .frame(width: fit.width, height: fit.height)
                    .padding(max(fit.width, fit.height) * percent / 100)
                    .background(color)
                    .shadow(radius: 2)
            }
            if sources.isEmpty {
                Text("Drop images here")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(sources) { source in
                            HStack {
                                Text(source.name)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button("Remove", systemImage: "xmark.circle.fill") {
                                    sources.removeAll { $0.id == source.id }
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .frame(maxHeight: 100)
            }
            Button("Choose Images…", action: chooseImages)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [5])
                )
        )
    }

    private func chooseImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        var failed = 0
        for url in panel.urls {
            do {
                try sources.append(BorderToolService.loadSource(at: url))
            } catch {
                failed += 1
            }
        }
        reportFailures(failed, "couldn't be added")
    }

    private func add(_ providers: [NSItemProvider]) async {
        var failed = 0
        for provider in providers {
            do {
                try await sources.append(BorderToolService.loadSource(from: provider))
            } catch {
                failed += 1
            }
        }
        reportFailures(failed, "couldn't be added")
    }

    private func apply() async {
        guard let target = resolveTarget() else { return }
        // Snapshot the settings so the whole batch gets one border.
        let percent = percent
        let borderColor = color.resolve(in: environment).cgColor
        var taken = Set<String>()
        if case let .folder(folder) = target {
            let existing = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            taken = Set(existing.map { $0.lowercased() })
        }
        isWorking = true
        var failedSources: [BorderSource] = []
        for source in sources {
            do {
                let output = try await BorderToolService.render(source, percent: percent, color: borderColor)
                switch target {
                case let .board(project):
                    try addToBoard(output, project: project)
                case let .folder(folder):
                    let name = uniqueBorderFileName(base: source.name, fileExtension: output.fileExtension, taken: taken)
                    // .withoutOverwriting: a file that appeared since the listing still never gets replaced.
                    try output.data.write(to: folder.appendingPathComponent(name, isDirectory: false), options: .withoutOverwriting)
                    taken.insert(name.lowercased())
                }
            } catch {
                failedSources.append(source)
            }
        }
        isWorking = false
        guard failedSources.isEmpty else {
            // Keep only what failed, so the user sees which files to retry.
            sources = failedSources
            reportFailures(failedSources.count, "couldn't be bordered")
            return
        }
        dismiss()
    }

    private func resolveTarget() -> Target? {
        switch destination {
        case .board:
            return projects.first { $0.id == boardID }.map(Target.board)
        case .folder:
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Save"
            guard panel.runModal() == .OK, let folder = panel.url else { return nil }
            return .folder(folder)
        }
    }

    /// A button action, never mid-gesture, so writing the model here is safe.
    private func addToBoard(_ output: BorderedImage, project: Project) throws {
        let size = aspectFit(pixelWidth: output.pixelWidth, pixelHeight: output.pixelHeight, maxEdge: ImageImportService.maxDisplayEdge)
        let bounds = boardContentBounds(project.items.map {
            (center: CGPoint(x: $0.positionX, y: $0.positionY), size: CGSize(width: $0.width, height: $0.height))
        })
        try ImageImportService.insertImage(
            data: output.data,
            fileExtension: output.fileExtension,
            into: project,
            at: appendedImportCenter(contentBounds: bounds, size: size),
            context: modelContext
        )
    }

    private func reportFailures(_ count: Int, _ outcome: String) {
        guard count > 0 else { return }
        failureMessage = count == 1 ? "1 image \(outcome)." : "\(count) images \(outcome)."
        isShowingFailure = true
    }
}
