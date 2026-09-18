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
                .tint(Theme.navy)
                .task {
                    // A quiet, no-UI sweep of anything left in 垃圾桶 past its retention
                    // window — same cleanup TrashView does in its own .onAppear, run here
                    // too so cards don't linger forever if the user never happens to open
                    // that screen. Deliberately does NOT touch notification permissions —
                    // that's requested lazily, only when the user turns on a follow-up
                    // reminder for a specific card (see CardFormView), not at launch.
                    TrashService.purgeExpired(context: sharedModelContainer.mainContext)
                    migrateLegacyFollowUpDates(context: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

/// One-time, idempotent migration from the old single `BusinessCard.followUpDate` to the new
/// `followUpTasks` list (see `FollowUpTask`). Safe to run on every launch — once a card's
/// `followUpDate` is nil there's nothing left for it to do, so this is cheap after the first run
/// on any given card. Runs right alongside `TrashService.purgeExpired` above, the same
/// "quiet startup sweep" pattern this app already uses for the trash's retention window.
private func migrateLegacyFollowUpDates(context: ModelContext) {
    guard let cards = try? context.fetch(FetchDescriptor<BusinessCard>()) else { return }
    for card in cards where card.followUpDate != nil {
        if let legacyDate = card.followUpDate {
            // The old build scheduled this under a different notification identifier (one per
            // card, not one per task) — cancel that before scheduling the new per-task one, so
            // an upgrade never leaves two notifications pending for what is now the same task.
            ReminderService.cancelLegacy(cardID: card.id)
            let task = FollowUpTask(dueDate: legacyDate)
            card.followUpTasks.append(task)
            ReminderService.schedule(cardID: card.id, name: card.name, task: task)
        }
        card.followUpDate = nil
    }
}
