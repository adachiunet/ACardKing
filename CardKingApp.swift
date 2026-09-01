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
                .task {
                    // A quiet, no-UI sweep of anything left in 垃圾桶 past its retention
                    // window — same cleanup TrashView does in its own .onAppear, run here
                    // too so cards don't linger forever if the user never happens to open
                    // that screen. Deliberately does NOT touch notification permissions —
                    // that's requested lazily, only when the user turns on a follow-up
                    // reminder for a specific card (see CardFormView), not at launch.
                    TrashService.purgeExpired(context: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
