//
//  FolderAppearanceTests.swift
//  moodyTests
//

import AppKit
import Testing
@testable import moody

struct FolderAppearanceTests {
    @Test func newFolderUsesDefaultAppearance() {
        let folder = Folder(name: "Folder")
        #expect(folder.resolvedIconName == FolderIcon.defaultName)
        #expect(folder.resolvedColor == FolderColor.defaultColor)
    }

    @Test func unknownStoredValuesFallBackToDefaults() {
        let folder = Folder(name: "Folder", iconName: "not.a.real.symbol", colorName: "chartreuse")
        #expect(folder.resolvedIconName == FolderIcon.defaultName)
        #expect(folder.resolvedColor == FolderColor.defaultColor)
    }

    @Test func knownStoredValuesAreUsed() {
        let folder = Folder(name: "Folder", iconName: "leaf", colorName: FolderColor.green.rawValue)
        #expect(folder.resolvedIconName == "leaf")
        #expect(folder.resolvedColor == .green)
    }

    @Test func everyCuratedIconIsARealSFSymbol() {
        #expect(FolderIcon.all.contains(FolderIcon.defaultName))
        #expect(Set(FolderIcon.all).count == FolderIcon.all.count)
        for name in FolderIcon.all {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name)")
        }
    }
}
