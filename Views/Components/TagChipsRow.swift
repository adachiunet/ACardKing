import SwiftUI

/// A horizontally-scrolling row of toggleable tag chips, backed by a `Set<Tag>` selection.
/// Reused both as a filter (CardListView) and as a multi-select picker (CardFormView,
/// BatchScanView's "apply to whole batch" tag picker).
struct TagChipsRow: View {
    let tags: [Tag]
    @Binding var selectedTags: Set<Tag>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags) { tag in
                    chip(for: tag)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func chip(for tag: Tag) -> some View {
        let isSelected = selectedTags.contains(tag)
        let color = Color(hex: tag.colorHex)
        return Button {
            if isSelected {
                selectedTags.remove(tag)
            } else {
                selectedTags.insert(tag)
            }
        } label: {
            Text(tag.name)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? color : color.opacity(0.15))
                .foregroundStyle(isSelected ? .white : color)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
