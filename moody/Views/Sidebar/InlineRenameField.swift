//
//  InlineRenameField.swift
//  moody
//
//  Finder-style in-place rename: takes focus as soon as it appears, commits on
//  Return or when focus moves away, cancels on Escape. Exactly one of
//  `onCommit` / `onCancel` is called per edit.
//

import SwiftUI

struct InlineRenameField: View {
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @State private var didFinish = false
    @FocusState private var isFocused: Bool

    init(name: String, onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onCommit = onCommit
        self.onCancel = onCancel
        _text = State(initialValue: name)
    }

    var body: some View {
        TextField("Name", text: $text)
            .labelsHidden()
            .focused($isFocused)
            .onSubmit { finish(commit: true) }
            .onExitCommand { finish(commit: false) }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    finish(commit: true)
                }
            }
            .task { await claimFocus() }
    }

    /// When rename is triggered by a double-click, the sidebar's outline view
    /// is still handling that click and keeps first responder, so a single
    /// focus request is silently dropped. Keep asking until focus lands (or
    /// the edit ends), instead of guessing a fixed delay.
    private func claimFocus() async {
        for _ in 0 ..< 20 where !isFocused && !didFinish {
            isFocused = true
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func finish(commit: Bool) {
        guard !didFinish else { return }
        didFinish = true
        if commit {
            onCommit(text)
        } else {
            onCancel()
        }
    }
}
