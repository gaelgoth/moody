//
//  BorderToolCommands.swift
//  moody
//
//  Tools ▸ Add Border… (⇧⌘B). The flag lives in the focused window's
//  RootView, so the sheet opens there and knows that window's open board.
//

import SwiftUI

extension FocusedValues {
    @Entry var showsBorderTool: Binding<Bool>?
}

struct BorderToolCommands: Commands {
    @FocusedBinding(\.showsBorderTool) private var showsBorderTool

    var body: some Commands {
        CommandMenu("Tools") {
            Button("Add Border…") {
                showsBorderTool = true
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(showsBorderTool == nil)
        }
    }
}
