//
//  ContainerView.swift
//  moody
//
//  A container's frame and header (icon + title). Its photos are ordinary
//  BoardItemViews positioned by relayout; this view only draws behind them.
//  Double-click (handled by the board) renames; right-click changes the
//  appearance or flips the axis.
//

import SwiftData
import SwiftUI

struct ContainerView: View {
    @Bindable var item: BoardItem
    let isEditing: Bool
    let isDropTarget: Bool
    let onEndEditing: () -> Void
    let menu: BoardItemMenu

    @Environment(\.modelContext) private var modelContext
    @State private var showsAppearance = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if item.stackedItems.isEmpty {
                Text("Drop photos here")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(item.resolvedColor.color.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: 10).strokeBorder(
                isDropTarget ? Color.accentColor : item.resolvedColor.color.opacity(0.5),
                lineWidth: isDropTarget ? 3 : 1
            )
        )
        .contextMenu {
            Button("Appearance…") { showsAppearance = true }
            Button(item.axis == .column ? "Switch to Row" : "Switch to Column", action: switchAxis)
            Divider()
            menu
        }
        .popover(isPresented: $showsAppearance) {
            FolderAppearancePicker(iconName: $item.iconName, colorName: $item.colorName)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: item.resolvedIconName)
                .foregroundStyle(item.resolvedColor.color)
            if isEditing {
                TextField("Untitled", text: $item.title)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit(onEndEditing)
                    .onExitCommand(perform: onEndEditing)
                    .onChange(of: isFocused) { _, focused in
                        if !focused {
                            onEndEditing()
                        }
                    }
                    .task { await claimFocus() }
            } else {
                Text(item.title.isEmpty ? "Untitled" : item.title)
                    .foregroundStyle(item.title.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .font(.headline)
        .padding(.horizontal, StackMetrics.padding)
        .frame(height: StackMetrics.headerHeight)
    }

    /// A context-menu click, never mid-gesture, so writing here is safe.
    private func switchAxis() {
        item.axis = item.axis == .column ? .row : .column
        relayout(item)
        try? modelContext.save()
    }

    /// Same as NoteCardView: the double-click is still being handled when the
    /// field appears, so keep asking for focus until it lands.
    private func claimFocus() async {
        for _ in 0 ..< 20 where !isFocused && isEditing {
            isFocused = true
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
