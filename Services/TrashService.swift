import Foundation
import SwiftData

/// Backs the 垃圾桶 (trash) behavior: a card the user deletes is only ever soft-deleted
/// (`BusinessCard.isDeleted = true`, `deletedAt` stamped — see `CardDetailView.deleteCard()`),
/// so a mis-tap can be undone from `TrashView`. This service is what actually reclaims the
/// space once a card has sat in the trash long enough that recovering it is no longer the
/// point — at which point its photos are removed from disk and the record itself is deleted
/// for real. Nothing here ever touches the network; it's just local cleanup.
enum TrashService {
    /// How long a soft-deleted card stays recoverable before it's purged for good. 30 days
    /// mirrors the "recently deleted" window most people are already used to from Photos/Mail.
    static let retentionDays = 30

    /// Permanently removes every soft-deleted card whose `deletedAt` is older than
    /// `retentionDays`. Safe to call often and from more than one place (app launch, opening
    /// the trash screen) — with nothing to purge it's just one cheap, empty fetch.
    static func purgeExpired(context: ModelContext) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: .now) else { return }
        // `Date.distantFuture` captured into a plain local constant first: the #Predicate macro
        // trips over a static member access like `Date.distantFuture` written directly inside
        // the predicate closure (confirmed via an actual Xcode build error — it tries to build a
        // KeyPath expression tree for it and fails to match the closure's expected result type).
        // A captured local `Date` value, by contrast, is exactly the kind of external reference
        // #Predicate is built to support.
        let distantFuture = Date.distantFuture
        let predicate = #Predicate<BusinessCard> { card in
            card.isDeleted && (card.deletedAt ?? distantFuture) < cutoff
        }
        guard let expired = try? context.fetch(FetchDescriptor<BusinessCard>(predicate: predicate)) else { return }
        for card in expired {
            permanentlyDelete(card, context: context)
        }
    }

    /// Removes one card for good, right now — used both by the automatic purge above and by
    /// TrashView's explicit "永久刪除" button. Cleans up the card's photo files and cancels any
    /// pending 追蹤提醒 notification before deleting the SwiftData record itself, so nothing is
    /// left dangling on disk or in the notification center.
    static func permanentlyDelete(_ card: BusinessCard, context: ModelContext) {
        ImageStorageService.delete(card.frontImagePath)
        ImageStorageService.delete(card.backImagePath)
        ReminderService.cancel(cardID: card.id)
        context.delete(card)
    }

    /// Undoes a soft delete — the card goes straight back to the main list.
    static func restore(_ card: BusinessCard) {
        card.isDeleted = false
        card.deletedAt = nil
    }
}
