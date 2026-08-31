import SwiftUI
import SwiftData

@main
struct CardKingApp: App {
    /// The one and only SwiftData store, entirely local — no CloudKit configuration,
    /// so nothing here ever leaves the device on its own.
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            BusinessCard.self,
            Tag.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("無法建立 ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            CardListView()
        }
        .modelContainer(sharedModelContainer)
    }
}
