import Foundation
import SwiftData

/// The core record: one scanned or manually entered business card.
/// Everything here lives only on-device (SwiftData local store, no CloudKit) —
/// this app never makes a network request.
@Model
final class BusinessCard {
    var id: UUID = UUID()
    var name: String = ""
    var jobTitle: String = ""
    /// 部門 — kept separate from jobTitle/company since a card commonly prints all three
    /// (e.g. 業務經理 / 業務部 / 台灣電子股份有限公司).
    var department: String = ""
    var company: String = ""
    var phones: [ContactField] = []
    var emails: [ContactField] = []
    var website: String = ""
    var address: String = ""
    /// 統一編號 — Taiwan's 8-digit business tax/registration number, commonly printed on
    /// company cards and invoices. Plain text, not validated (some cards print it with
    /// dashes/spaces, some don't) — kept exactly as scanned or typed.
    var taxId: String = ""
    var notes: String = ""
    /// Filenames (not full paths) inside ImageStorageService's directory. Optional because
    /// a manually-entered card may have no scanned photo at all.
    var frontImagePath: String?
    var backImagePath: String?
    /// Older front/back photos that got bumped when a newer scan replaced them during a
    /// duplicate-card merge (see `CardFormView.updateExisting()`) — never populated any other
    /// way. `frontImagePath`/`backImagePath` above always stay "the current photo for that
    /// side" (what the thumbnail, vCard export, etc. use), so nothing else in the app needs to
    /// know these exist; `CardDetailView` shows them in a collapsed "更早的照片" strip so they
    /// aren't just silently kept out of sight. Added instead of turning the two paths above
    /// into arrays specifically to avoid a SwiftData schema-type change on a field real
    /// installs already have data in — purely additive fields default safely for old records.
    var additionalFrontImagePaths: [String] = []
    var additionalBackImagePaths: [String] = []
    var dateAdded: Date = Date.now
    var dateModified: Date = Date.now
    /// Marks this card as the user's OWN business card, as opposed to someone else's — set
    /// via a toggle in CardFormView. Only ever one card carries this flag at a time (enforced
    /// in CardFormView.save(), which clears it on any other card when a new one is marked);
    /// MyCardView reads it to show the "我的名片" screen (photo + QR code + share sheet).
    var isMyCard: Bool = false

    /// 我的最愛 — a quick "I care about staying in touch with this person" flag, independent
    /// of tags. Surfaced as a star toggle in CardDetailView/CardRow and as a "只看最愛" filter
    /// in CardListView.
    var isFavorite: Bool = false

    /// 追蹤提醒（舊版單一日期）— superseded by `followUpTasks` below, kept only so a card written
    /// by an older installed build still decodes. `CardKingApp.migrateLegacyFollowUpDates` folds
    /// any value still sitting here into a first `FollowUpTask` at app launch, then clears it —
    /// nothing else in the app reads or writes this field going forward.
    var followUpDate: Date?

    /// 追蹤任務清單 — a card can carry more than one pending follow-up at once (e.g. "9/20 加
    /// LINE"、"10/1 寄簡報"), each with its own local notification (see `ReminderService`).
    /// Purely additive relative to the old single `followUpDate` field above — same reasoning as
    /// `additionalFrontImagePaths` elsewhere on this model: an old record simply defaults to an
    /// empty list here until migrated.
    var followUpTasks: [FollowUpTask] = []

    /// 互動紀錄 — a growing, timestamped log ("met at the expo", "discussed the contract"),
    /// as opposed to `notes` which stays a single free-text field for anything that isn't
    /// naturally a dated entry. Same "array of Codable struct" storage pattern as `phones`/
    /// `emails`. Newest-first ordering is a presentation concern, not enforced here.
    var interactions: [InteractionEntry] = []

    /// Soft-delete flag. Deleting a card in the UI no longer removes it from the store
    /// immediately — it's flagged here (and `deletedAt` stamped) so it can be restored from
    /// the 垃圾桶 (TrashView) screen. `CardListView`'s `@Query` filters these out of the main
    /// list; `TrashService` permanently removes anything past its retention window.
    var isDeleted: Bool = false
    var deletedAt: Date?

    @Relationship(inverse: \Tag.cards)
    var tags: [Tag] = []

    init(
        name: String = "",
        jobTitle: String = "",
        department: String = "",
        company: String = "",
        phones: [ContactField] = [],
        emails: [ContactField] = [],
        website: String = "",
        address: String = "",
        taxId: String = "",
        notes: String = "",
        frontImagePath: String? = nil,
        backImagePath: String? = nil,
        additionalFrontImagePaths: [String] = [],
        additionalBackImagePaths: [String] = [],
        isMyCard: Bool = false,
        isFavorite: Bool = false,
        followUpDate: Date? = nil,
        followUpTasks: [FollowUpTask] = [],
        interactions: [InteractionEntry] = []
    ) {
        self.id = UUID()
        self.name = name
        self.jobTitle = jobTitle
        self.department = department
        self.company = company
        self.phones = phones
        self.emails = emails
        self.website = website
        self.address = address
        self.taxId = taxId
        self.notes = notes
        self.frontImagePath = frontImagePath
        self.backImagePath = backImagePath
        self.additionalFrontImagePaths = additionalFrontImagePaths
        self.additionalBackImagePaths = additionalBackImagePaths
        self.isMyCard = isMyCard
        self.isFavorite = isFavorite
        self.followUpDate = followUpDate
        self.followUpTasks = followUpTasks
        self.interactions = interactions
        self.isDeleted = false
        self.deletedAt = nil
        self.dateAdded = .now
        self.dateModified = .now
    }
}
