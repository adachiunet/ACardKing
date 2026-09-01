import Foundation

/// One dated log entry on a card — "met at the expo on 8/1", "talked about the partnership on
/// 9/1" — kept as a growing list rather than a single overwritable `notes` field, so a card's
/// history with this person builds up over time instead of the last note replacing the ones
/// before it. Stored directly as an array (`[InteractionEntry]`) on `BusinessCard`, the same
/// pattern as `ContactField` — SwiftData persists an array of a `Codable` value type natively,
/// no separate table/relationship needed.
struct InteractionEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var text: String

    init(date: Date = .now, text: String) {
        self.id = UUID()
        self.date = date
        self.text = text
    }
}
