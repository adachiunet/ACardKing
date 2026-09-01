import Foundation

/// Turns the plain-text vCard payload of a scanned QR code into the same `ParsedCardFields`
/// the OCR flow produces, so a QR-code business card and a photographed one land in the exact
/// same review form afterward. This only ever runs on text already decoded from a QR code the
/// user scanned with their own camera — nothing is fetched or looked up over the network.
///
/// Deliberately only understands the same vCard 3.0 shape `ExportService` itself writes (plus
/// the common variations other apps' vCard exports use) — a hand-rolled parser for the full
/// vCard spec isn't worth it for "read back a QR code someone put on their own digital card".
enum VCardParser {
    /// Returns nil when `text` doesn't look like a vCard at all (e.g. the QR code was just a
    /// URL or plain text) — callers should fall back to showing the raw scanned text instead
    /// of silently producing an empty card.
    static func parse(_ text: String) -> ParsedCardFields? {
        guard text.uppercased().contains("BEGIN:VCARD") else { return nil }

        var result = ParsedCardFields()
        result.rawText = text

        for line in unfoldLines(text) {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let rawProperty = String(line[line.startIndex..<colonIndex])
            let rawValue = String(line[line.index(after: colonIndex)...])
            let value = unescape(rawValue)

            // A property can carry parameters after a ";" (e.g. "TEL;TYPE=CELL,VOICE").
            let propertyParts = rawProperty.split(separator: ";", maxSplits: 1)
            guard let propertyName = propertyParts.first?.uppercased() else { continue }
            let paramsPart = propertyParts.count > 1 ? String(propertyParts[1]).uppercased() : ""

            switch propertyName {
            case "FN":
                if result.name.isEmpty { result.name = value }
            case "N" where result.name.isEmpty:
                // "N" is "Family;Given;Middle;Prefix;Suffix" — only used as a fallback when
                // there's no "FN" line at all, joined back into one display name.
                let components = value.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
                let given = components.count > 1 ? components[1] : ""
                let family = components.first ?? ""
                result.name = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
            case "TITLE":
                result.jobTitle = value
            case "ORG":
                // "Company;OrganizationalUnit" — see ExportService.vCard(for:), which writes
                // 部門 as the org's second component when present.
                let components = value.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                result.company = components.first ?? value
                if components.count > 1 { result.department = components[1] }
            case "TEL":
                let (number, ext) = splitExtension(from: value)
                result.phones.append(ContactField(type: fieldType(from: paramsPart), value: number, ext: ext))
            case "EMAIL":
                result.emails.append(ContactField(type: fieldType(from: paramsPart), value: value))
            case "URL":
                if result.website.isEmpty { result.website = value }
            case "ADR":
                let components = value.split(separator: ";", omittingEmptySubsequences: true).map(String.init)
                let joined = components.joined(separator: " ")
                if !joined.isEmpty { result.address = joined }
            case "X-TAXID":
                result.taxId = value
            default:
                break
            }
        }

        return result
    }

    /// RFC 2426 §5.8.1 line folding: a continuation line starts with a single space or tab and
    /// should be joined onto the previous logical line with that leading whitespace stripped.
    /// `ExportService.foldBase64` (and most other vCard writers) fold long lines this way, so
    /// unfolding first is what keeps a wrapped TEL/ADR/PHOTO line from being read as garbage.
    private static func unfoldLines(_ text: String) -> [String] {
        let rawLines = text.components(separatedBy: .newlines)
        var result: [String] = []
        for line in rawLines {
            if let first = line.first, (first == " " || first == "\t"), !result.isEmpty {
                result[result.count - 1] += line.dropFirst()
            } else if !line.isEmpty {
                result.append(line)
            }
        }
        return result
    }

    private static func fieldType(from paramsPart: String) -> ContactField.FieldType {
        if paramsPart.contains("CELL") || paramsPart.contains("MOBILE") { return .mobile }
        if paramsPart.contains("FAX") { return .fax }
        if paramsPart.contains("HOME") { return .home }
        if paramsPart.contains("WORK") { return .work }
        return .other
    }

    /// `ExportService.vCard(for:)` writes a phone extension as " 分機88" appended to the plain
    /// TEL value text (vCard 3.0 has no dedicated slot for one) — this reverses that so a
    /// re-scanned CardKing-exported vCard round-trips its extension back into its own field
    /// instead of leaving "0912345678 分機88" sitting in the phone number itself.
    private static func splitExtension(from value: String) -> (number: String, ext: String) {
        guard let range = value.range(of: " 分機") else { return (value, "") }
        let number = String(value[value.startIndex..<range.lowerBound])
        let ext = String(value[range.upperBound...])
        return (number, ext)
    }

    /// Reverses the backslash-escaping vCard values use for characters that would otherwise be
    /// ambiguous with the format's own delimiters — the same escaping `ExportService` applies
    /// to `NOTE` (`\` → `\\`, newline → `\n`), plus the standard `\,` / `\;` other vCard writers
    /// commonly use.
    private static func unescape(_ value: String) -> String {
        var result = ""
        var iterator = value.makeIterator()
        while let char = iterator.next() {
            if char == "\\", let next = iterator.next() {
                switch next {
                case "n", "N": result.append("\n")
                case ",": result.append(",")
                case ";": result.append(";")
                case "\\": result.append("\\")
                default: result.append(next)
                }
            } else {
                result.append(char)
            }
        }
        return result
    }
}
