//
//  FolderAppearancePicker.swift
//  moody
//
//  Popover for choosing a folder's or board container's color and SF Symbol
//  icon from the curated sets in FolderAppearance.swift. Changes apply (and
//  save) immediately.
//

import SwiftData
import SwiftUI

struct FolderAppearancePicker: View {
    @Binding var iconName: String
    @Binding var colorName: String
    @Environment(\.modelContext) private var modelContext

    private var selectedColor: FolderColor {
        FolderColor(rawValue: colorName) ?? FolderColor.defaultColor
    }

    private var selectedIcon: String {
        FolderIcon.all.contains(iconName) ? iconName : FolderIcon.defaultName
    }

    private let iconColumns = Array(repeating: GridItem(.fixed(32), spacing: 6), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Color")
                .font(.headline)
            HStack(spacing: 6) {
                ForEach(FolderColor.allCases) { folderColor in
                    colorSwatch(folderColor)
                }
            }

            Text("Icon")
                .font(.headline)
            LazyVGrid(columns: iconColumns, spacing: 6) {
                ForEach(FolderIcon.all, id: \.self) { iconName in
                    iconButton(iconName)
                }
            }
        }
        .padding(14)
    }

    private func colorSwatch(_ folderColor: FolderColor) -> some View {
        let isSelected = selectedColor == folderColor
        return Button {
            colorName = folderColor.rawValue
            try? modelContext.save()
        } label: {
            Circle()
                .fill(folderColor.color)
                .frame(width: 20, height: 20)
                .padding(3)
                .overlay(Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.6 : 0), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(folderColor.displayName)
        .accessibilityLabel(folderColor.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func iconButton(_ iconName: String) -> some View {
        let isSelected = selectedIcon == iconName
        let tint = selectedColor.color
        return Button {
            self.iconName = iconName
            try? modelContext.save()
        } label: {
            Image(systemName: iconName)
                .font(.title3)
                .frame(width: 32, height: 32)
                .foregroundStyle(isSelected ? Color.white : tint)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? tint : Color.secondary.opacity(0.1))
                )
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(iconName)
        .accessibilityLabel(iconName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    FolderAppearancePicker(iconName: .constant("sparkles"), colorName: .constant("purple"))
        .modelContainer(for: [Folder.self, Project.self, BoardItem.self, BoardConnector.self], inMemory: true)
}
