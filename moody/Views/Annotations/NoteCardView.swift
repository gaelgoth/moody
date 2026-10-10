//
//  NoteCardView.swift
//  moody
//
//  A sticky-note card: the note's text on a pastel of its FolderColor.
//  Dark text on a light card regardless of the board's background. While
//  editing, the TextEditor writes the model live (typing is not a gesture);
//  the board saves when editing ends.
//

import SwiftData
import SwiftUI

struct NoteCardView: View {
    @Bindable var item: BoardItem
    let isEditing: Bool
    let onEndEditing: () -> Void
    let menu: BoardItemMenu

    @Environment(\.modelContext) private var modelContext
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextEditor(text: $item.text)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(Color.black.opacity(0.85))
                    .focused($isFocused)
                    .onExitCommand(perform: onEndEditing)
                    .onChange(of: isFocused) { _, focused in
                        if !focused {
                            onEndEditing()
                        }
                    }
                    .onChange(of: item.text) { fitNoteHeight(item) }
                    .task { await claimFocus() }
            } else {
                Text(item.text.isEmpty ? "Note" : item.text)
                    .foregroundStyle(Color.black.opacity(item.text.isEmpty ? 0.35 : 0.85))
                    .padding(.horizontal, NoteMetrics.editorInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .font(.system(size: NoteMetrics.fontSize))
        .padding(NoteMetrics.padding)
        .background(card)
        .contextMenu {
            Picker("Color", selection: colorBinding) {
                ForEach(FolderColor.allCases) { color in
                    Text(color.displayName).tag(color)
                }
            }
            Divider()
            menu
        }
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 6).fill(item.resolvedColor.color.opacity(0.35)))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
    }

    /// A context-menu click, never mid-gesture, so saving here is safe.
    private var colorBinding: Binding<FolderColor> {
        Binding(
            get: { item.resolvedColor },
            set: { color in
                item.colorName = color.rawValue
                try? modelContext.save()
            }
        )
    }

    /// The double-click that started editing is still being handled when the
    /// editor appears, so one focus request can be dropped (same as
    /// InlineRenameField): keep asking until it lands.
    private func claimFocus() async {
        for _ in 0 ..< 20 where !isFocused && isEditing {
            isFocused = true
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
