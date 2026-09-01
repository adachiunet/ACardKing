import SwiftUI
import SwiftData

/// A small, entirely local snapshot of the card collection — no network call, no third-party
/// analytics, just a few counts computed on-device from whatever SwiftData already has fetched.
/// "我的名片" (the user's own card) is excluded from every count here — it isn't someone the
/// user met, so it would otherwise skew "how many contacts do I have" and "which company shows
/// up most" numbers.
struct StatsView: View {
    @Query(filter: #Predicate<BusinessCard> { !$0.isDeleted && !$0.isMyCard })
    private var cards: [BusinessCard]

    private var thisMonthCount: Int {
        let calendar = Calendar.current
        return cards.filter { calendar.isDate($0.dateAdded, equalTo: .now, toGranularity: .month) }.count
    }

    private var favoriteCount: Int { cards.filter(\.isFavorite).count }
    private var pendingFollowUpCount: Int { cards.filter { $0.followUpDate != nil }.count }

    private var topCompanies: [(name: String, count: Int)] {
        grouped(cards.map(\.company))
    }

    private var topTags: [(name: String, count: Int)] {
        grouped(cards.flatMap { $0.tags.map(\.name) })
    }

    var body: some View {
        List {
            Section("總覽") {
                LabeledContent("名片總數", value: "\(cards.count)")
                LabeledContent("本月新增", value: "\(thisMonthCount)")
                LabeledContent("我的最愛", value: "\(favoriteCount)")
                LabeledContent("待追蹤提醒", value: "\(pendingFollowUpCount)")
            }

            if !topCompanies.isEmpty {
                Section("公司分布(前 10)") {
                    ForEach(topCompanies.prefix(10), id: \.name) { entry in
                        LabeledContent(entry.name, value: "\(entry.count)")
                    }
                }
            }

            if !topTags.isEmpty {
                Section("標籤分布(前 10)") {
                    ForEach(topTags.prefix(10), id: \.name) { entry in
                        LabeledContent(entry.name, value: "\(entry.count)")
                    }
                }
            }
        }
        .navigationTitle("名片統計")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Groups non-empty values by exact text match and returns them sorted by count, most
    /// common first — used for both the company and tag breakdowns above.
    private func grouped(_ values: [String]) -> [(name: String, count: Int)] {
        let nonEmpty = values.filter { !$0.isEmpty }
        let counts = Dictionary(grouping: nonEmpty, by: { $0 }).mapValues(\.count)
        return counts.map { (name: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
    }
}
