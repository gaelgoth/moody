//
//  moodyApp.swift
//  moody
//
//  Created by Gaël Gothuey on 21.09.2026.
//

import SwiftData
import SwiftUI

@main
struct moodyApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Folder.self,
            Project.self,
            BoardItem.self,
        ])
        // UI tests pass -inMemoryStore so they never touch the user's real library.
        let inMemory = ProcessInfo.processInfo.arguments.contains("-inMemoryStore")
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
