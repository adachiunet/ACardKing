import Foundation
import UIKit

/// Wraps whatever should go into the share sheet for one export action (a vCard/CSV/backup
/// file, and — when exporting a single scanned card — its original photo files alongside it)
/// so it can be used with SwiftUI's `.sheet(item:)` (a plain array isn't Identifiable).
struct ExportFile: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// "Send to someone else" exports — vCard for importing into Contacts-like apps, CSV for
/// opening in a spreadsheet. For a full-fidelity backup of this app's own data (including
/// tags and photos, meant to be re-imported into CardKing itself), see BackupService instead.
enum ExportService {

    // MARK: - vCard (.vcf)

    static func vCard(for card: BusinessCard) -> String {
        var lines = ["BEGIN:VCARD", "VERSION:3.0"]
        lines.append("FN:\(card.name.isEmpty ? "未命名" : card.name)")
        if !card.company.isEmpty || !card.department.isEmpty {
            // RFC 2426's ORG value is structured as "Organization;OrganizationalUnit1;...",
            // so 部門 rides along as the organizational unit when present.
            let org = card.department.isEmpty ? card.company : "\(card.company);\(card.department)"
            lines.append("ORG:\(org)")
        }
        if !card.jobTitle.isEmpty {
            lines.append("TITLE:\(card.jobTitle)")
        }
        for phone in card.phones {
            // vCard 3.0's TEL has no standard slot for an extension number, so — same as most
            // real-world address books — it's appended to the human-readable value itself
            // rather than dropped.
            let value = phone.ext.isEmpty ? phone.value : "\(phone.value) 分機\(phone.ext)"
            lines.append("TEL;TYPE=\(phone.type.rawValue.uppercased()):\(value)")
        }
        for email in card.emails {
            lines.append("EMAIL;TYPE=\(email.type.rawValue.uppercased()):\(email.value)")
        }
        if !card.website.isEmpty {
            lines.append("URL:\(card.website)")
        }
        if !card.address.isEmpty {
            lines.append("ADR;TYPE=WORK:;;\(card.address);;;;")
        }
        if !card.taxId.isEmpty {
            // Not a standard vCard property — there isn't one for a tax/business-registration
            // ID — so this rides along as a custom X- extension. Per RFC 2426, readers that
            // don't recognize an X- property must just ignore it rather than choke on it, so
            // this is safe to include but isn't guaranteed to actually be shown by whatever
            // app the vCard is opened in (Apple Contacts, for one, won't display it anywhere).
            lines.append("X-TAXID:\(card.taxId)")
        }
        if !card.notes.isEmpty {
            let escapedNotes = card.notes
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\n", with: "\\n")
            lines.append("NOTE:\(escapedNotes)")
        }
        if let photoLine = vCardPhotoLine(for: card.frontImagePath) {
            lines.append(photoLine)
        }
        lines.append("END:VCARD")
        return lines.joined(separator: "\r\n")
    }

    /// vCard 3.0's PHOTO property (base64), so the front photo travels with the contact when
    /// imported elsewhere — e.g. Apple Contacts shows it as the contact's photo automatically.
    /// Only the front photo is embedded (vCard readers generally expect one PHOTO per card);
    /// the back photo — and both photos in full resolution — are still exportable as separate
    /// files (see CardDetailView's "匯出這張名片") and are both included in a full backup
    /// (BackupService).
    ///
    /// Long lines are "folded" per RFC 2426 §5.8.1 (continuation lines start with a single
    /// space) so mail/Contacts apps that expect properly-folded vCards don't choke on one
    /// giant line.
    private static func vCardPhotoLine(for frontImagePath: String?) -> String? {
        guard let image = ImageStorageService.load(frontImagePath),
              let data = image.jpegData(compressionQuality: 0.7) else {
            return nil
        }
        let prefix = "PHOTO;ENCODING=b;TYPE=JPEG:"
        return prefix + foldBase64(data.base64EncodedString(), firstLineBudget: 75 - prefix.count)
    }

    private static func foldBase64(_ base64: String, firstLineBudget: Int) -> String {
        var remaining = Substring(base64)
        var lines: [String] = []
        var budget = max(firstLineBudget, 1)
        while !remaining.isEmpty {
            let take = min(budget, remaining.count)
            lines.append(String(remaining.prefix(take)))
            remaining = remaining.dropFirst(take)
            budget = 74 // continuation lines start with one folding space, so 74 + 1 = 75
        }
        return lines.joined(separator: "\r\n ")
    }

    static func vCard(for cards: [BusinessCard]) -> String {
        cards.map { vCard(for: $0) }.joined(separator: "\r\n")
    }

    static func writeVCardFile(cards: [BusinessCard], filename: String = "名片.vcf") -> URL? {
        writeTempFile(content: vCard(for: cards), filename: filename)
    }

    // MARK: - CSV

    static func csv(for cards: [BusinessCard]) -> String {
        var rows = ["姓名,職稱,部門,公司,電話,Email,網站,地址,統一編號,標籤,備註,建立日期"]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        for card in cards {
            let phones = card.phones
                .map { $0.ext.isEmpty ? $0.value : "\($0.value) 分機\($0.ext)" }
                .joined(separator: "; ")
            let emails = card.emails.map { $0.value }.joined(separator: "; ")
            let tags = card.tags.map { $0.name }.joined(separator: "; ")
            let fields = [
                card.name, card.jobTitle, card.department, card.company, phones, emails,
                card.website, card.address, card.taxId, tags, card.notes,
                formatter.string(from: card.dateAdded)
            ]
            rows.append(fields.map(csvEscape).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    static func writeCSVFile(cards: [BusinessCard], filename: String = "名片.csv") -> URL? {
        writeTempFile(content: csv(for: cards), filename: filename)
    }

    private static func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }

    private static func writeTempFile(content: String, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("ExportService write error: \(error)")
            return nil
        }
    }
}
