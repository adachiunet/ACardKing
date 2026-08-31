import SwiftUI
import UIKit

/// One row in the main card list: a small avatar (photo if available, initial otherwise),
/// name, company/title, and up to a few tag chips.
struct CardRow: View {
    let card: BusinessCard

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 4) {
                Text(card.name.isEmpty ? "未命名" : card.name)
                    .font(.headline)
                let subtitle = [card.jobTitle, card.department, card.company]
                    .filter { !$0.isEmpty }.joined(separator: " · ")
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !card.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(card.tags.prefix(3)) { tag in
                            TagChip(tag: tag)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var avatar: some View {
        if let path = card.frontImagePath, let image = ImageStorageService.load(path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(card.name.isEmpty ? "?" : String(card.name.prefix(1)))
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                )
        }
    }
}
