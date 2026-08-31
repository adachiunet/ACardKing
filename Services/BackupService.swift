import Foundation
import SwiftData

/// The round-trippable backup format: every card's text fields and its tags (by name), in one
/// self-contained JSON file. This is what "匯出再匯入" is built on — no cloud account, no
/// server, just a file the user moves around however they like (Files app, AirDrop, a cloud
/// drive folder) and re-opens later, on this phone or a new one.
///
/// Carries each card's photo by FILENAME REFERENCE only (`frontImagePath`/`backImagePath`,
/// e.g. "3F2A...-1B.jpg") — never the image bytes. This is deliberate: embedding base64 photos
/// made every export several times larger and slower to generate/share, and it's unnecessary
/// for the common case, because a card's photo inside the app (`CardDetailView`) is always
/// resolved by looking up that same filename in local storage via `ImageStorageService` —
/// completely independent of this export/import feature. So importing this JSON on the SAME
/// device (e.g. after Xcode re-signs an expired free-provisioning build) auto-reconnects every
/// photo for free, because the actual JPEG files never left `Documents/CardImages` — re-signing
/// only refreshes the code-signature, it does not touch the app's Data container.
///
/// The one case this format alone can't cover is moving to a genuinely different device (or a
/// truly fresh install with a new Data container): the filenames in the JSON will point at
/// files that don't exist there yet, so those cards import with no photo until the actual JPEG
/// files are also copied into `Documents/CardImages` — e.g. via Finder's file-sharing view (see
/// SETUP.md) — using the same filenames, at which point the very same import auto-relinks them
/// with no further action.
struct BackupPayload: Codable {
    var exportedAt: Date
    var tags: [BackupTag]
    var cards: [BackupCard]
}

struct BackupTag: Codable {
    var name: String
    var colorHex: String
}

struct BackupCard: Codable {
    var name: String
    var jobTitle: String
    var department: String
    var company: String
    var phones: [ContactField]
    var emails: [ContactField]
    var website: String
    var address: String
    var taxId: String
    var notes: String
    var tagNames: [String]
    var dateAdded: Date
    var dateModified: Date
    var frontImagePath: String?
    var backImagePath: String?
    /// Added alongside BusinessCard.isMyCard. Defaults to false when decoding an older backup
    /// file that predates this field, so importing a pre-existing export never crashes.
    var isMyCard: Bool = false
}

enum BackupService {

    // MARK: - Export

    static func writeBackupFile(cards: [BusinessCard], tags: [Tag]) -> URL? {
        let backupTags = tags.map { BackupTag(name: $0.name, colorHex: $0.colorHex) }
        let backupCards = cards.map { card -> BackupCard in
            BackupCard(
                name: card.name,
                jobTitle: card.jobTitle,
                department: card.department,
                company: card.company,
                phones: card.phones,
                emails: card.emails,
                website: card.website,
                address: card.address,
                taxId: card.taxId,
                notes: card.notes,
                tagNames: card.tags.map { $0.name },
                dateAdded: card.dateAdded,
                dateModified: card.dateModified,
                frontImagePath: card.frontImagePath,
                backImagePath: card.backImagePath,
                isMyCard: card.isMyCard
            )
        }
        let payload = BackupPayload(exportedAt: .now, tags: backupTags, cards: backupCards)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return nil }

        let stampFormatter = DateFormatter()
        stampFormatter.dateFormat = "yyyyMMdd-HHmm"
        let filename = "CardKing備份-\(stampFormatter.string(from: .now)).json"

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            return url
        } catch {
            print("BackupService.writeBackupFile error: \(error)")
            return nil
        }
    }

    // MARK: - Import

    /// Reads a previously-exported backup file and inserts everything into `modelContext`.
    /// Tags are matched to `existingTags` by exact name so re-importing doesn't create
    /// duplicate tags; every card in the file becomes a *new* BusinessCard record — import
    /// does not attempt to detect or merge duplicate cards. Each card's frontImagePath/
    /// backImagePath is carried over as-is (a filename, not image data — see the note on
    /// BackupPayload above): if a JPEG with that exact filename already exists in
    /// `Documents/CardImages` on this device, the photo just shows up automatically; if not,
    /// the card imports fine with that field simply not resolving to anything yet (no crash,
    /// no error — `ImageStorageService.load`/`fileURL` treat a missing file as "no photo").
    /// Returns the number of cards imported, or nil if the file couldn't be read/decoded at all.
    static func importBackup(from url: URL, into modelContext: ModelContext, existingTags: [Tag]) -> Int? {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
        }

        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(BackupPayload.self, from: data) else { return nil }

        var tagLookup: [String: Tag] = [:]
        for tag in existingTags { tagLookup[tag.name] = tag }
        for backupTag in payload.tags where tagLookup[backupTag.name] == nil {
            let tag = Tag(name: backupTag.name, colorHex: backupTag.colorHex)
            modelContext.insert(tag)
            tagLookup[backupTag.name] = tag
        }

        for backupCard in payload.cards {
            let card = BusinessCard(
                name: backupCard.name,
                jobTitle: backupCard.jobTitle,
                department: backupCard.department,
                company: backupCard.company,
                phones: backupCard.phones,
                emails: backupCard.emails,
                website: backupCard.website,
                address: backupCard.address,
                taxId: backupCard.taxId,
                notes: backupCard.notes,
                frontImagePath: backupCard.frontImagePath,
                backImagePath: backupCard.backImagePath,
                isMyCard: backupCard.isMyCard
            )
            card.dateAdded = backupCard.dateAdded
            card.dateModified = backupCard.dateModified
            card.tags = backupCard.tagNames.compactMap { tagLookup[$0] }
            modelContext.insert(card)
        }

        // A re-imported backup could carry a card flagged "我的名片" on top of one already
        // marked on this device (or the backup itself, in theory, could carry more than one
        // if it came from an older build) — CardFormView.save() is what normally keeps this
        // to a single card, but that guard is bypassed here since import inserts directly.
        // Re-apply the same "only one" rule now: keep whichever was modified most recently.
        let allMyCards = ((try? modelContext.fetch(FetchDescriptor<BusinessCard>())) ?? [])
            .filter(\.isMyCard)
        if allMyCards.count > 1 {
            for dupe in allMyCards.sorted(by: { $0.dateModified > $1.dateModified }).dropFirst() {
                dupe.isMyCard = false
            }
        }

        return payload.cards.count
    }
}
