//
//  NoteGeometry.swift
//  moody
//
//  Sizing for note cards: fixed width, height fitted to the text.
//

import AppKit

enum NoteMetrics {
    static let width: Double = 220
    static let padding: Double = 12
    static let minHeight: Double = 80
    static let fontSize: Double = 14
    /// TextEditor's line-fragment padding on each side; NoteCardView pads
    /// static text by the same amount so it doesn't shift when editing starts.
    static let editorInset: Double = 5
}

/// Card height that fits `text` wrapped at `width`, never below `NoteMetrics.minHeight`.
func noteHeight(text: String, width: Double = NoteMetrics.width) -> Double {
    let textWidth = width - 2 * (NoteMetrics.padding + NoteMetrics.editorInset)
    let bounds = NSAttributedString(
        string: text,
        attributes: [.font: NSFont.systemFont(ofSize: NoteMetrics.fontSize)]
    ).boundingRect(
        with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    return max(NoteMetrics.minHeight, ceil(bounds.height) + 2 * NoteMetrics.padding + 2 * NoteMetrics.editorInset)
}

/// Resizes `note` to fit its text, growing downward (top edge fixed). Caller saves.
func fitNoteHeight(_ note: BoardItem) {
    let top = note.positionY - note.height / 2
    note.height = noteHeight(text: note.text, width: note.width)
    note.positionY = top + note.height / 2
}
