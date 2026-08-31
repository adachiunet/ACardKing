import SwiftUI

/// A small read-only colored pill showing one tag's name. Used in list rows and detail views.
struct TagChip: View {
    let tag: Tag

    var body: some View {
        Text(tag.name)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(hex: tag.colorHex).opacity(0.15))
            .foregroundStyle(Color(hex: tag.colorHex))
            .clipShape(Capsule())
    }
}
