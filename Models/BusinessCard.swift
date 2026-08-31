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
    var dateAdded: Date = Date.now
    var dateModified: Date = Date.now
    /// Marks this card as the user's OWN business card, as opposed to someone else's — set
    /// via a toggle in CardFormView. Only ever one card carries this flag at a time (enforced
    /// in CardFormView.save(), which clears it on any other card when a new one is marked);
    /// MyCardView reads it to show the "我的名片" screen (photo + QR code + share sheet).
    var isMyCard: Bool = false

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
        isMyCard: Bool = false
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
        self.isMyCard = isMyCard
        self.dateAdded = .now
        self.dateModified = .now
    }
}
