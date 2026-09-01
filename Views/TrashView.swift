import SwiftUI
import SwiftData

/// 垃圾桶 — cards deleted from CardDetailView land here (soft-deleted, not actually removed;
/// see `BusinessCard.isDeleted`/`deletedAt`) so a mis-tap can be undone. Anything left here
/// past `TrashService.retentionDays` is purged automatically (both on app launch and every
/// time this screen opens); "永久刪除" does the same thing immediately, on demand.
struct TrashView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<BusinessCard> { $0.isDeleted },
        sort: [SortDescriptor(\BusinessCard.deletedAt, order: .reverse)]
    )
    private var deletedCards: [BusinessCard]

    var body: some View {
        Group {
            if deletedCards.isEmpty {
                ContentUnavailableView(
                    "垃圾桶是空的",
                    systemImage: "trash",
                    description: Text("刪除的名片會先留在這裡 \(TrashService.retentionDays) 天,可以隨時復原。")
                )
            } else {
                List {
                    Section {
                        ForEach(deletedCards) { card in
                            row(for: card)
                        }
                    } footer: {
                        Text("超過 \(TrashService.retentionDays) 天沒有復原的名片,會自動永久刪除(含照片)。")
                    }
                }
            }
        }
        .navigationTitle("垃圾桶")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            TrashService.purgeExpired(context: modelContext)
        }
    }

    private func row(for card: BusinessCard) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.name.isEmpty ? "未命名" : card.name)
                    .font(.headline)
                let subtitle = [card.jobTitle, card.company].filter { !$0.isEmpty }.joined(separator: " · ")
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let deletedAt = card.deletedAt {
                    Text("刪除於 \(deletedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("復原") {
                TrashService.restore(card)
            }
            .buttonStyle(.bordered)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                TrashService.permanentlyDelete(card, context: modelContext)
            } label: {
                Label("永久刪除", systemImage: "trash")
            }
        }
    }
}
