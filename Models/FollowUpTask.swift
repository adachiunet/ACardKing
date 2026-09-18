import Foundation

/// One follow-up reminder on a card. Replaces the old single `BusinessCard.followUpDate` (kept
/// on the model only for old-data migration — see `CardKingApp.migrateLegacyFollowUpDates`) with
/// a growing list, so a contact can carry more than one pending thing to do at once (e.g. "9/20
/// 加 LINE"、"10/1 寄簡報") instead of only ever a single date. Same storage pattern as
/// `ContactField`/`InteractionEntry` — a `Codable` value type kept directly in an array on
/// `BusinessCard`, no separate SwiftData relationship needed.
///
/// Each task gets its own local notification, scheduled/cancelled independently by `id` (see
/// `ReminderService`) — completing or deleting one task never touches any other task's
/// notification.
struct FollowUpTask: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var dueDate: Date
    /// Optional short note on what this follow-up is actually about ("寄簡報", "問報價") —
    /// shown alongside the date wherever the task appears. Empty is fine; not every reminder
    /// needs an explanation beyond "follow up with this person".
    var note: String = ""
    /// Marked, not deleted, when done — so a card's follow-up history stays visible (CardDetailView
    /// shows completed tasks struck through) instead of disappearing the moment it's handled.
    /// `ReminderService.syncAll` cancels the notification for any task with this set to true.
    var isCompleted: Bool = false

    init(dueDate: Date, note: String = "", isCompleted: Bool = false) {
        self.id = UUID()
        self.dueDate = dueDate
        self.note = note
        self.isCompleted = isCompleted
    }
}
