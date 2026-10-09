//
//  SidebarSelection.swift
//  moody
//
//  Sidebar selection and drag payload. Both identify rows by UUID rather than
//  holding model objects, so they stay valid across `@Query` refreshes and can
//  be encoded for drag and drop.
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated enum SidebarSelection: Hashable, Codable {
    case folder(UUID)
    case board(UUID)
}

/// Drag payload for moving sidebar rows. Declared in Info.plist under
/// `UTExportedTypeDeclarations` so the system recognizes the custom type.
nonisolated struct SidebarItemReference: Hashable, Codable, Transferable {
    var selection: SidebarSelection

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .moodySidebarItem)
    }
}

nonisolated extension UTType {
    static let moodySidebarItem = UTType(exportedAs: "gaelgothuey.moodyboard.sidebar-item", conformingTo: .data)
}
