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
            Project.self,
            BoardItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

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
