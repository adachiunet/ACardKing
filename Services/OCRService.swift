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
                result.emails.append(ContactField(type: .other, value: String(line[matchRange])))
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
                    result.phones.append(ContactField(type: .other, value: candidate, ext: ext))
                    continue
                }
            }

            remainingLines.append(line)
        }

        if remainingLines.count > 0 { result.name = remainingLines[0] }
        if remainingLines.count > 1 { result.jobTitle = remainingLines[1] }
        if remainingLines.count > 2 { result.company = remainingLines[2] }
        if remainingLines.count > 3 {
            result.address = remainingLines[3...].joined(separator: " ")
        }
        // 部門 (department) is deliberately NOT guessed here — line position alone can't
        // reliably tell a department line apart from a second job-title line or the company
        // name, and a wrong guess would be worse than leaving it blank. It stays blank after
        // scanning; the review screen lets the user type it in directly.

        return result
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
    /// before saving.
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
    /// translation) are kept side by side.
    private static func combine(_ a: String, _ b: String, separator: String = " / ") -> String {
        let a = a.trimmingCharacters(in: .whitespaces)
        let b = b.trimmingCharacters(in: .whitespaces)
        if a.isEmpty { return b }
        if b.isEmpty || a == b { return a }
        return "\(a)\(separator)\(b)"
    }

    private static func dedupContactFields(_ fields: [ContactField]) -> [ContactField] {
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
