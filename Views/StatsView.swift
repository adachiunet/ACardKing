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

            Section {
                LabeledContent("App 版本", value: appVersionString)
            } footer: {
                Text("每次重新裝新的 .ipa 之後,可以在這裡確認手機上這支 App 是不是真的換成新版本了——如果這個版本號跟你剛下載那次的 Actions 編譯沒有對上,代表裝到手機上的還是舊的那份。")
            }
        }
        .navigationTitle("名片統計")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "1.0 (build 3)" style — reads straight from the app bundle's Info.plist
    /// (CFBundleShortVersionString / CFBundleVersion, set in project.yml's MARKETING_VERSION /
    /// CURRENT_PROJECT_VERSION), not anything this view computes itself, so it can't drift out
    /// of sync with whatever was actually compiled into the running binary. This exists purely
    /// as an on-device diagnostic: several rounds of this project's real-device testing turned
    /// out to be testing a build that predated whatever change was actually being checked,
    /// which was impossible to tell apart from a genuine code bug without something like this.
    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = info?["CFBundleVersion"] as? String ?? "?"
        return "\(shortVersion) (build \(buildNumber))"
    }

    /// Groups non-empty values by exact text match and returns them sorted by count, most
    /// common first — used for both the company and tag breakdowns above.
    private func grouped(_ values: [String]) -> [(name: String, count: Int)] {
        let nonEmpty = values.filter { !$0.isEmpty }
        let counts = Dictionary(grouping: nonEmpty, by: { $0 }).mapValues(\.count)
        return counts.map { (name: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
    }
}
