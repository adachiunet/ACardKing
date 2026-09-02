import Foundation
import Vision
import UIKit

/// The best-effort result of parsing OCR'd text lines from a single business-card photo.
/// This is always a starting point, not a final answer — the UI always lets the user
/// review and correct these fields before anything is saved.
struct ParsedCardFields {
    var name: String = ""
    var jobTitle: String = ""
    var department: String = ""
    var company: String = ""
    var phones: [ContactField] = []
    var emails: [ContactField] = []
    var website: String = ""
    var address: String = ""
    /// 統一編號 — only ever set when a recognized label (統一編號/統編/統一编号) is found next
    /// to the digits (see `taxIdRegex`), never guessed from a bare number, to avoid mistaking
    /// an 8-digit phone number for a tax ID.
    var taxId: String = ""
    var rawText: String = ""
}

/// Fully on-device text recognition (Vision framework) + a simple heuristic field parser.
/// No network request is ever made — this is what keeps card scanning offline.
enum OCRService {
    private static let emailRegex = try? NSRegularExpression(
        pattern: #"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
    )
    private static let phoneRegex = try? NSRegularExpression(
        pattern: #"(\+?\d[\d\-\s\(\)]{6,}\d)"#
    )
    private static let urlRegex = try? NSRegularExpression(
        pattern: #"((https?://)?(www\.)?[A-Za-z0-9-]+\.[A-Za-z]{2,}(/[^\s]*)?)"#
    )
    /// Matches a phone extension mentioned on the same line as the number itself
    /// ("02-1234-5678 分機88", "ext.88", "#88", "轉88") and captures just the digits.
    private static let extRegex = try? NSRegularExpression(
        pattern: #"(?:分機|ext\.?|轉|转)[:：\s]*([0-9]{1,6})"#, options: [.caseInsensitive]
    )

    /// Legal-entity suffixes that reliably mark a line as the company name, wherever it sits
    /// on the card — a logo or a stacked layout means the company often ISN'T the third line
    /// down the way plain top-to-bottom text order would suggest, so this is checked before
    /// falling back to position.
    ///
    /// The bare "公司" (not just the fuller "有限公司"/"股份有限公司") is deliberately included:
    /// the user pointed out that a lot of real company names on cards just end in "XX公司"
    /// without the full legal "股份有限公司"/"有限公司" suffix actually appearing on that line
    /// (e.g. wrapped onto a second line, or the card just prints the short form) — the previous
    /// list only matched the fuller forms, so a bare "XX科技公司" line fell through to the
    /// positional guess and got mistaken for a person's name whenever it was the first line.
    /// "公司" alone is a safe, high-precision signal for Chinese business cards: it's very rare
    /// for that word to show up in a name/title/address line, so widening to it shouldn't
    /// introduce new misfires. Also broadened with more of the common Taiwan business-entity
    /// words and international suffixes that don't include "公司"/"Ltd"/"Inc" at all.
    private static let companyKeywords = [
        "公司", "企業", "實業", "工業", "科技", "資訊", "生技", "生醫", "醫療", "貿易",
        "國際", "集團", "控股", "投資", "顧問", "設計", "建設", "開發", "文創", "傳媒",
        "企業社", "工作室", "事務所", "商行", "行號",
        "Co., Ltd", "Co.,Ltd", "Ltd.", "Inc.", "Corp.", "LLC", "LLP", "Group",
        "Technology", "Technologies", "Solutions", "Systems", "Enterprises",
        "International", "Industries", "Holdings", "Consulting", "Studio"
    ]

    /// Address markers. Checked together with "the line has a digit in it" (see `parse`) so
    /// a job title like "市場部經理" (which contains 市 but no house/floor number) doesn't get
    /// misfiled as an address just because it shares a character with a real street name.
    private static let addressKeywords = [
        "路", "街", "道", "巷", "弄", "號", "樓", "室", "區", "市", "縣",
        "Road", "Rd.", "Street", "St.", "Ave", "Avenue", "Floor", "District"
    ]

    /// Runs on-device text recognition on the given image and returns the recognized lines,
    /// ordered top-to-bottom, left-to-right (a best-effort approximation of reading order).
    static func recognizeText(in image: UIImage, completion: @escaping ([String]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            guard error == nil, let observations = request.results as? [VNRecognizedTextObservation] else {
                completion([])
                return
            }
            // Vision's normalized coordinate system has its origin at the bottom-left,
            // so a larger y is higher up on the card.
            let sorted = observations.sorted { lhs, rhs in
                if abs(lhs.boundingBox.origin.y - rhs.boundingBox.origin.y) > 0.02 {
                    return lhs.boundingBox.origin.y > rhs.boundingBox.origin.y
                }
                return lhs.boundingBox.origin.x < rhs.boundingBox.origin.x
            }
            let lines = sorted.compactMap { $0.topCandidates(1).first?.string }
            completion(lines)
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hant", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("OCRService.recognizeText error: \(error)")
                DispatchQueue.main.async { completion([]) }
            }
        }
    }

    /// Heuristic field parser: regex-matches phone/email/website lines out of the text,
    /// then guesses name/title/company from the remaining lines by their vertical order
    /// (business cards conventionally put the name first, then title, then company).
    /// This is intentionally simple — it's a starting point for the user to correct,
    /// not an attempt at true field understanding.
    static func parse(lines: [String]) -> ParsedCardFields {
        var result = ParsedCardFields()
        result.rawText = lines.joined(separator: "\n")

        var remainingLines: [String] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)

            if let regex = emailRegex,
               let match = regex.firstMatch(in: line, range: range),
               let matchRange = Range(match.range, in: line) {
                // Default to 公司 (work) rather than 其他 (other) — a scanned card's email is
                // a company address in the overwhelming majority of cases, and the field is
                // always editable afterward if this one happens to be personal.
                result.emails.append(ContactField(type: .work, value: String(line[matchRange])))
                continue
            }

            // 統一編號/統編 — only ever trusted when that exact label is present on the line,
            // so a bare string of digits (which could just as easily be a phone number) never
            // gets mistaken for a tax ID.
            if line.contains("統一編號") || line.contains("統編") {
                let digits = line.filter(\.isNumber)
                if digits.count >= 6 {
                    result.taxId = digits
                    continue
                }
            }

            let lowercased = line.lowercased()
            if lowercased.contains("www.") || lowercased.contains("http") {
                if let regex = urlRegex,
                   let match = regex.firstMatch(in: line, range: range),
                   let matchRange = Range(match.range, in: line) {
                    result.website = String(line[matchRange])
                    continue
                }
            }

            if let regex = phoneRegex,
               let match = regex.firstMatch(in: line, range: range),
               let matchRange = Range(match.range, in: line) {
                let candidate = String(line[matchRange]).trimmingCharacters(in: .whitespaces)
                let digitCount = candidate.filter { $0.isNumber }.count
                if digitCount >= 7 {
                    var ext = ""
                    if let extRegexObj = extRegex,
                       let extMatch = extRegexObj.firstMatch(in: line, range: range),
                       let extGroupRange = Range(extMatch.range(at: 1), in: line) {
                        ext = String(line[extGroupRange])
                    }
                    // 10 digits is a Taiwan mobile number (09xx-xxx-xxx); anything else scanned
                    // off a business card (a landline with area code, a toll-free line) defaults
                    // to 公司 (work) rather than 其他 (other) — both are still editable afterward.
                    let phoneType: ContactField.FieldType = digitCount == 10 ? .mobile : .work
                    result.phones.append(ContactField(type: phoneType, value: candidate, ext: ext))
                    continue
                }
            }

            remainingLines.append(line)
        }

        // Company and address are pulled out by keyword wherever they appear, BEFORE the
        // positional guess below runs — a line with a company legal suffix or a street
        // number is almost never mistaken for something else, whereas "the company name is
        // always the 3rd line" breaks the moment a card leads with a logo, a slogan, or the
        // company name in bigger type at the very top.
        var positionalLines: [String] = []
        var addressLines: [String] = []
        for line in remainingLines {
            if result.company.isEmpty, containsAny(line, companyKeywords) {
                result.company = line
                continue
            }
            if containsAny(line, addressKeywords), line.contains(where: \.isNumber) {
                addressLines.append(line)
                continue
            }
            positionalLines.append(line)
        }

        if positionalLines.count > 0 { result.name = positionalLines[0] }
        if positionalLines.count > 1 { result.jobTitle = positionalLines[1] }
        var nextIndex = 2
        if result.company.isEmpty, positionalLines.count > 2 {
            result.company = positionalLines[2]
            nextIndex = 3
        }
        if positionalLines.count > nextIndex {
            addressLines.append(contentsOf: positionalLines[nextIndex...])
        }
        if !addressLines.isEmpty {
            result.address = addressLines.joined(separator: " ")
        }
        // 部門 (department) is deliberately NOT guessed here — line position alone can't
        // reliably tell a department line apart from a second job-title line or the company
        // name, and a wrong guess would be worse than leaving it blank. It stays blank after
        // scanning; the review screen lets the user type it in directly.

        return result
    }

    private static func containsAny(_ line: String, _ keywords: [String]) -> Bool {
        keywords.contains { line.localizedCaseInsensitiveContains($0) }
    }

    /// True when front and back disagree on at least one of the fields `merge` would
    /// otherwise silently join with " / " (most often a Chinese/English bilingual card).
    /// The scan flow uses this to decide whether to show the user an explicit "combine
    /// these?" screen instead of just merging without asking.
    static func divergentFields(front: ParsedCardFields, back: ParsedCardFields) -> Bool {
        func differs(_ a: String, _ b: String) -> Bool {
            let a = a.trimmingCharacters(in: .whitespaces)
            let b = b.trimmingCharacters(in: .whitespaces)
            return !a.isEmpty && !b.isEmpty && a != b
        }
        return differs(front.name, back.name)
            || differs(front.jobTitle, back.jobTitle)
            || differs(front.company, back.company)
            || differs(front.website, back.website)
            || differs(front.address, back.address)
    }

    /// Merges the front and back photo's OCR guesses into the one set of fields that gets
    /// saved on the card. Many business cards (especially in Taiwan) put the same text in
    /// two languages on the two sides — e.g. a Chinese name/title/company on the front and
    /// the English equivalent on the back — so when both sides found *different* text for
    /// name/title/company/website, both are kept together (joined with " / ") rather than
    /// the back's version being silently thrown away. Phone numbers and emails from both
    /// sides are combined and de-duplicated, and both sides' raw text is kept so the review
    /// screen can show exactly what was read from each side if needed. This is still only a
    /// starting guess — the review screen always lets the user trim or fix the combined text
    /// before saving. (The scan flow now only reaches this silently when `divergentFields`
    /// is false; when fields actually disagree, `FrontBackMergeReviewView` asks first and
    /// this just supplies its "both" default.)
    static func merge(front: ParsedCardFields, back: ParsedCardFields?) -> ParsedCardFields {
        guard let back else { return front }

        var merged = front
        merged.name = combine(front.name, back.name)
        merged.jobTitle = combine(front.jobTitle, back.jobTitle)
        merged.department = combine(front.department, back.department)
        merged.company = combine(front.company, back.company)
        merged.website = combine(front.website, back.website)
        merged.address = combine(front.address, back.address, separator: "；")
        merged.taxId = combine(front.taxId, back.taxId)

        merged.phones = dedupContactFields(front.phones + back.phones)
        merged.emails = dedupContactFields(front.emails + back.emails)
        merged.rawText = "【正面】\n\(front.rawText)\n\n【反面】\n\(back.rawText)"
        return merged
    }

    /// Joins two guesses for the same field: empty ones drop out, identical ones collapse to
    /// one, and two different non-empty values (e.g. a Chinese name and its English
    /// translation) are kept side by side. Not `private` — `CardFormView.updateExisting()`
    /// reuses this same convention when merging a duplicate-card update into an existing
    /// record, so the two merge features (front/back OCR, duplicate-card update) read and
    /// behave the same way instead of drifting into two different conventions.
    static func combine(_ a: String, _ b: String, separator: String = " / ") -> String {
        let a = a.trimmingCharacters(in: .whitespaces)
        let b = b.trimmingCharacters(in: .whitespaces)
        if a.isEmpty { return b }
        if b.isEmpty || a == b { return a }
        return "\(a)\(separator)\(b)"
    }

    /// Same idea as `combine`, but for joining a freshly-entered value onto a field that may
    /// already be the product of one or more *previous* merges — used by
    /// `CardFormView.updateExisting()` when the same real-world contact gets re-scanned or
    /// re-entered multiple times over the life of the card. Plain `combine` would happily keep
    /// growing "黃 / huang" into "黃 / huang / huang / HUANG" every time the same variant shows
    /// up again; this guards against that by skipping the append when `existing` already
    /// contains `new` (case-insensitive), so a repeat sighting of a variant already on record
    /// is a no-op instead of another copy tacked on.
    static func combineIntoExisting(_ existing: String, _ new: String, separator: String = " / ") -> String {
        let existing = existing.trimmingCharacters(in: .whitespaces)
        let new = new.trimmingCharacters(in: .whitespaces)
        if new.isEmpty { return existing }
        if existing.isEmpty { return new }
        if existing == new || existing.localizedCaseInsensitiveContains(new) { return existing }
        return "\(existing)\(separator)\(new)"
    }

    /// Not `private` for the same reason as `combine` above — `CardFormView.updateExisting()`
    /// reuses this to merge an existing card's phones/emails with a newly-entered set instead
    /// of overwriting them outright.
    static func dedupContactFields(_ fields: [ContactField]) -> [ContactField] {
        var seenValues = Set<String>()
        var result: [ContactField] = []
        for field in fields {
            let key = field.value.trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty, !seenValues.contains(key) else { continue }
            seenValues.insert(key)
            result.append(field)
        }
        return result
    }
}
