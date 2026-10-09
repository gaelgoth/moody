//
//  FolderAppearance.swift
//  moody
//
//  The curated icons and colors a folder can use. Folders store plain
//  strings, so unknown values (e.g. a symbol renamed in a future OS) fall
//  back to the defaults instead of rendering a blank icon.
//

import SwiftUI

enum FolderColor: String, CaseIterable, Identifiable {
    case red
    case orange
    case yellow
    case green
    case mint
    case teal
    case blue
    case indigo
    case purple
    case pink
    case brown
    case gray

    static let defaultColor: FolderColor = .blue

    var id: String {
        rawValue
    }

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        case .gray: .gray
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}

enum FolderIcon {
    static let defaultName = "folder"

    static let all = [
        "folder", "star", "heart", "sparkles", "paintpalette", "paintbrush",
        "camera", "photo", "film", "music.note", "book", "lightbulb",
        "house", "building.2", "briefcase", "person.2", "tshirt", "gift",
        "leaf", "flame", "drop", "bolt", "cloud", "sun.max",
        "moon", "globe", "airplane", "car", "pawprint", "cup.and.saucer",
        "fork.knife", "tag",
    ]
}

extension Folder {
    var resolvedIconName: String {
        FolderIcon.all.contains(iconName) ? iconName : FolderIcon.defaultName
    }

    var resolvedColor: FolderColor {
        FolderColor(rawValue: colorName) ?? FolderColor.defaultColor
    }
}
