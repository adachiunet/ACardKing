import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Persisted sort choices for the home list. Raw values are stored directly in `@AppStorage`
/// (as a String), so renaming a case's raw value would silently reset users' saved preference —
/// keep these stable once shipped.
enum CardSortOption: String, CaseIterable, Identifiable {
    case name, dateAddedDesc, dateModifiedDesc, company

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .name: return "姓名"
        case .dateAddedDesc: return "新增時間(新到舊)"
        case .dateModifiedDesc: return "修改時間(新到舊)"
        case .company: return "公司"
        }
    }
}

/// The app's home screen: search、tag-filter, and the full list of cards, plus every
/// entry point for adding cards (manual, single scan, batch camera scan, batch photo-library
/// import) and for the app's data-portability features (vCard/CSV export, full backup
/// export/import).
struct CardListView: View {
    @Environment(\.modelContext) private var modelContext
    // Excludes soft-deleted cards (see BusinessCard.isDeleted / TrashView) — a card the user
    // deleted should disappear from the home list immediately even though the record itself
    // is kept around for the trash's 30-day undo window. Sort is applied afterward in
    // `filteredCards` (below) since the chosen CardSortOption can change at runtime while a
    // static `@Query` sort descriptor can't easily follow an @AppStorage value.
    @Query(filter: #Predicate<BusinessCard> { !$0.isDeleted }, sort: \BusinessCard.name)
    private var allCards: [BusinessCard]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @State private var searchText = ""
    @State private var selectedTags: Set<Tag> = []
    @State private var favoritesOnly = false
    @AppStorage("cardSortOption") private var sortOption: CardSortOption = .name

    @State private var showingManualForm = false
    @State private var showingScan = false
    @State private var showingBatchScan = false
    @State private var showingBatchPhotoImport = false
    @State private var showingQRScan = false
    @State private var showingTagManager = false
    @State private var showingImporter = false
    @State private var showingMyCard = false
    @State private var showingTrash = false
    @State private var showingStats = false

    @State private var exportFile: ExportFile?
    @State private var importResultMessage = ""
    @State private var showingImportResult = false

    private var filteredCards: [BusinessCard] {
        // `localizedStandardContains` is Apple's "search-as-you-type" comparison — it's built
        // for Spotlight-style matching, which for CJK text (no spaces to mark word boundaries)
        // effectively requires the query to be a PREFIX of the whole string, not a substring
        // found anywhere inside it. That's why searching "黃" against a name like "陳大文
        // (黃小明介紹)" — or really any hit that isn't at position 0 — was returning nothing.
        // `range(of:options:)` below is a plain, unambiguous "does this substring appear
        // anywhere" search (still case- and diacritic-insensitive), which is what a "narrows
        // as you type more characters" search box actually needs.
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = allCards.filter { card in
            let matchesTags = selectedTags.isEmpty || !Set(card.tags).isDisjoint(with: selectedTags)
            guard matchesTags else { return false }
            guard !favoritesOnly || card.isFavorite else { return false }
            guard !query.isEmpty else { return true }

            let haystacks = [card.name, card.company, card.jobTitle, card.department, card.taxId, card.notes]
                + card.phones.map { $0.value }
                + card.emails.map { $0.value }
                + card.tags.map { $0.name }
            return haystacks.contains {
                $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
        switch sortOption {
        case .name:
            return matched.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .dateAddedDesc:
            return matched.sorted { $0.dateAdded > $1.dateAdded }
        case .dateModifiedDesc:
            return matched.sorted { $0.dateModified > $1.dateModified }
        case .company:
            return matched.sorted { $0.company.localizedStandardCompare($1.company) == .orderedAscending }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !allTags.isEmpty {
                    TagChipsRow(tags: allTags, selectedTags: $selectedTags)
                        .padding(.horizontal)
                }
                filterBar
                content
            }
            .navigationTitle("AcardKing")
            .navigationDestination(for: BusinessCard.self) { card in
                CardDetailView(card: card)
            }
            .searchable(text: $searchText, prompt: "搜尋姓名、公司、備註、標籤…")
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingManualForm) {
                NavigationStack {
                    CardFormView(existingCard: nil, prefilled: nil, prefilledFrontImagePath: nil, prefilledBackImagePath: nil)
                }
            }
            .sheet(isPresented: $showingScan) {
                ScanCardView()
            }
            .sheet(isPresented: $showingBatchScan) {
                BatchScanView(source: .camera)
            }
            .sheet(isPresented: $showingBatchPhotoImport) {
                BatchScanView(source: .photoLibrary)
            }
            .sheet(isPresented: $showingQRScan) {
                ScanQRCardView()
            }
            .sheet(isPresented: $showingTagManager) {
                NavigationStack { TagManagerView() }
            }
            .sheet(isPresented: $showingMyCard) {
                MyCardView()
            }
            .sheet(isPresented: $showingTrash) {
                NavigationStack { TrashView() }
            }
            .sheet(isPresented: $showingStats) {
                NavigationStack { StatsView() }
            }
            .sheet(item: $exportFile) { file in
                ShareSheet(items: file.items)
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                handleImportResult(result)
            }
            .alert(importResultMessage, isPresented: $showingImportResult) {
                Button("好") {}
            }
        }
    }

    /// "只看最愛" toggle + sort picker, sitting right above the list. Kept as a lightweight
    /// row rather than folded into the tag-chips row above, since tags/favorites/sort are
    /// conceptually three independent filters, not variations of one control.
    private var filterBar: some View {
        HStack {
            Button {
                favoritesOnly.toggle()
            } label: {
                Label("只看最愛", systemImage: favoritesOnly ? "star.fill" : "star")
                    .font(.footnote)
                    .foregroundStyle(favoritesOnly ? .yellow : .secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Picker("排序", selection: $sortOption) {
                ForEach(CardSortOption.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .font(.footnote)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var content: some View {
        if filteredCards.isEmpty {
            ContentUnavailableView(
                allCards.isEmpty ? "還沒有名片" : "找不到符合的名片",
                systemImage: "person.crop.rectangle.stack",
                description: Text(allCards.isEmpty ? "點右上角「+」開始新增" : "試試其他關鍵字或標籤")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(filteredCards) { card in
                    NavigationLink(value: card) {
                        CardRow(card: card)
                    }
                }
                .onDelete(perform: deleteCards)
            }
            .listStyle(.plain)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Custom principal view replaces the plain-text nav title with the App Icon artwork
        // next to the wordmark, so the brand mark on the home screen and inside the app match.
        // `.navigationTitle("AcardKing")` above is left in place — SwiftUI still uses it for the
        // back-button label ("< AcardKing") on CardDetailView, which has no principal item of its own.
        ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("AcardKing")
                    .font(.headline)
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button {
                    showingScan = true
                } label: {
                    Label("掃描一張名片(正+反面)", systemImage: "camera.viewfinder")
                }
                Button {
                    showingBatchScan = true
                } label: {
                    Label("批次掃描多張名片", systemImage: "square.stack.3d.up")
                }
                Button {
                    showingBatchPhotoImport = true
                } label: {
                    Label("批次選圖建立", systemImage: "photo.stack")
                }
                Button {
                    showingQRScan = true
                } label: {
                    Label("掃描 QR 名片", systemImage: "qrcode.viewfinder")
                }
                Button {
                    showingManualForm = true
                } label: {
                    Label("手動輸入", systemImage: "square.and.pencil")
                }
            } label: {
                Image(systemName: "plus")
            }
        }
        ToolbarItem(placement: .navigationBarLeading) {
            Menu {
                Button {
                    showingMyCard = true
                } label: {
                    Label("我的名片", systemImage: "person.crop.rectangle")
                }
                Divider()
                Button {
                    showingStats = true
                } label: {
                    Label("名片統計", systemImage: "chart.bar")
                }
                Button {
                    showingTrash = true
                } label: {
                    Label("垃圾桶", systemImage: "trash")
                }
                Divider()
                Button {
                    showingTagManager = true
                } label: {
                    Label("管理標籤", systemImage: "tag")
                }
                Divider()
                Button {
                    exportVCard()
                } label: {
                    Label("匯出全部 (vCard)", systemImage: "square.and.arrow.up")
                }
                Button {
                    exportCSV()
                } label: {
                    Label("匯出全部 (CSV)", systemImage: "tablecells")
                }
                Divider()
                Button {
                    exportBackup()
                } label: {
                    Label("完整備份匯出", systemImage: "arrow.down.doc")
                }
                Button {
                    showingImporter = true
                } label: {
                    Label("從備份匯入", systemImage: "arrow.up.doc")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    /// Swipe-to-delete from the list uses the same soft-delete as CardDetailView's delete —
    /// the card moves to 垃圾桶 (TrashView) instead of being removed immediately, so a swipe
    /// that goes a little too far can still be undone.
    private func deleteCards(at offsets: IndexSet) {
        for index in offsets {
            let card = filteredCards[index]
            card.isDeleted = true
            card.deletedAt = .now
            ReminderService.cancel(cardID: card.id)
        }
    }

    /// Bulk vCard export embeds each card's front photo inside its own VCARD block
    /// (ExportService does this automatically) but doesn't also attach every card's raw
    /// image files separately — with dozens of cards that would turn one export into a
    /// share sheet full of loose photos. For the original full-resolution photos of one
    /// specific card, use "匯出這張名片" from that card's detail screen instead.
    private func exportVCard() {
        if let url = ExportService.writeVCardFile(cards: allCards) {
            exportFile = ExportFile(items: [url])
        }
    }

    private func exportCSV() {
        if let url = ExportService.writeCSVFile(cards: allCards) {
            exportFile = ExportFile(items: [url])
        }
    }

    /// The backup JSON stays small (fields + tags + each card's photo FILENAME, not the image
    /// bytes — see the note on BackupPayload in BackupService.swift). Re-importing it on the
    /// SAME device (the normal case, e.g. after Xcode re-signs an expired free-provisioning
    /// build) reconnects every photo automatically, because the actual JPEGs never left this
    /// device's storage — signing expiry doesn't touch app data. Importing on a different
    /// device only brings the photos back once the actual JPEG files are also copied into
    /// Documents/CardImages there (e.g. via Finder file sharing — see SETUP.md).
    private func exportBackup() {
        if let url = BackupService.writeBackupFile(cards: allCards, tags: allTags) {
            exportFile = ExportFile(items: [url])
        }
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            if let count = BackupService.importBackup(from: url, into: modelContext, existingTags: allTags) {
                importResultMessage = "已匯入 \(count) 張名片"
            } else {
                importResultMessage = "匯入失敗,請確認選的是本 App 匯出的備份檔"
            }
        case .failure:
            importResultMessage = "匯入失敗,請確認選的是本 App 匯出的備份檔"
        }
        showingImportResult = true
    }
}
