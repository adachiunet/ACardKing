import Foundation
import SwiftData

/// A user-defined label for organizing business cards (e.g. "客戶", "供應商", "2026展會").
/// Many-to-many with `BusinessCard`; the inverse relationship is declared on `BusinessCard.tags`.
@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#4A90D9"
    var cards: [BusinessCard] = []

    init(name: String, colorHex: String = "#4A90D9") {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
    }
}
