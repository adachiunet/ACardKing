import Foundation

/// A single multi-value contact detail (a phone number or an email address)
/// with a user-facing label such as "手機" or "公司".
/// Stored directly as an array (`[ContactField]`) on `BusinessCard` via SwiftData's
/// native support for Codable value types.
struct ContactField: Codable, Identifiable, Hashable {
    enum FieldType: String, Codable, CaseIterable {
        case mobile, work, home, fax, other

        var displayName: String {
            switch self {
            case .mobile: return "手機"
            case .work: return "公司"
            case .home: return "住家"
            case .fax: return "傳真"
            case .other: return "其他"
            }
        }
    }

    var id: UUID = UUID()
    var type: FieldType
    var value: String
    /// Extension number (分機), meaningful only for phone entries — left empty for emails
    /// and for phones that don't have one. Kept as a separate field rather than baked into
    /// `value` so the UI can show/edit it in its own small box next to the number.
    var ext: String = ""

    init(type: FieldType, value: String, ext: String = "") {
        self.id = UUID()
        self.type = type
        self.value = value
        self.ext = ext
    }
}
