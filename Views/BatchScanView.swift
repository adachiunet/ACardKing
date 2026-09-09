import SwiftUI
import SwiftData
import UIKit

/// One item in a batch-scan session: one captured card-front photo plus its OCR guess, held
/// in memory until the user reaches (and confirms) its turn in the one-at-a-time review —
/// nothing is written to SwiftData before that. `backImagePath`/`parsed` can end up carrying
/// a second photo's worth of content when the user pairs two consecutive items in
/// `pairingStage` as the front/back of the same physical card — see `mergeItem(at:)`.
private struct BatchScanItem: Identifiable {
    let id = UUID()
    var image: UIImage
    var frontImagePath: String?
    var backImagePath: String?
    var parsed = ParsedCardFields()
}

/// Batch-add flow: gets a whole stack of card-front photos in one go — either freshly captured
/// via the system document scanner's native multi-page capture, or picked from photos already
/// sitting in the library (e.g. business-card photos someone sent over Messages/LINE) — runs
/// OCR on each, lets the user pick a shared set of tags to apply to the whole batch, then walks
/// through the cards ONE AT A TIME using the exact same full-field review form as a single scan
/// (CardFormView), so every field can be checked/fixed and nothing gets saved without an
/// explicit "儲存" tap per card. Every picked/scanned image starts out as its own card (one
/// photo = one card, front only) — capture order and photo-library selection order aren't
/// reliable signals for "these two images are the same physical card's two sides", so nothing
/// is paired automatically. Between OCR and tag setup, `pairingStage` instead lets the user
/// explicitly mark "this one is the back of the previous one" for any cards that need it (a
/// bilingual card whose front and back got captured as two separate images in the same batch
/// run) — those two items fold into one via `mergeItem(at:)`, reusing the same
/// `OCRService.merge` the single-card scan flow (ScanCardView) uses for front+back, so a card
/// paired this way ends up identical to one scanned via "掃描一張名片". Anything the user
/// doesn't explicitly pair stays exactly as it was: one photo, one card, no guessing.
struct BatchScanView: View {
    /// Where this batch's photos come from — the two entry points in CardListView's "+" menu.
    enum Source {
        case camera
        case photoLibrary
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tag.name) private var allTags: [Tag]

    var source: Source = .camera

    private enum Stage {
        case scanning
        case processing
        /// Let the user mark any consecutive pair of captures as the same card's front/back
        /// before tags or the one-at-a-time review begin — see `pairingStage`.
        case pairing
        /// Pick tags to carry into every card's form before starting the one-at-a-time walk.
        case tagSetup
        case reviewing
        case empty
    }

    @State private var stage: Stage = .scanning
    @State private var items: [BatchScanItem] = []
    @State private var processedCount = 0
    @State private var batchTags: Set<Tag> = []
    @State private var newTagName = ""
    @State private var showingNewTagField = false

    @State private var currentIndex = 0
    @State private var savedCount = 0

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .scanning:
                    switch source {
                    case .camera:
                        DocumentScannerView(
                            onScan: { images in handleScans(images) },
                            onCancel: { dismiss() }
                        )
                    case .photoLibrary:
                        PhotoPickerView(
                            onPick: { images in handleScans(images) },
                            onCancel: { dismiss() }
                        )
                    }
                case .processing:
                    ProgressView("辨識中(\(processedCount)/\(items.count))")
                case .pairing:
                    pairingStage
                case .tagSetup:
                    tagSetupView
                case .reviewing:
                    if currentIndex < items.count {
                        CardFormView(
                            existingCard: nil,
                            prefilled: items[currentIndex].parsed,
                            prefilledFrontImagePath: items[currentIndex].frontImagePath,
                            prefilledBackImagePath: items[currentIndex].backImagePath,
                            prefilledTags: batchTags,
                            onSaved: { _ in advance(saved: true) },
                            onCancelled: { advance(saved: false) }
                        )
                        .id(items[currentIndex].id)
                    } else {
                        doneView
                    }
                case .empty:
                    ContentUnavailableView(
                        source == .camera ? "沒有掃到任何名片" : "沒有選取任何照片",
                        systemImage: source == .camera ? "camera" : "photo.on.rectangle"
                    )
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if case .pairing = stage {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                }
                if case .tagSetup = stage {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                }
            }
        }
    }

    private var navigationTitle: String {
        if case .reviewing = stage, currentIndex < items.count {
            return "確認第 \(currentIndex + 1)/\(items.count) 張"
        }
        return source == .camera ? "批次掃描" : "批次選圖建立"
    }

    /// Lets the user explicitly mark "this photo is the back of the previous one" for any
    /// consecutive pair in the batch that turned out to be the two sides of the same physical
    /// card — see the doc-comment on `BatchScanItem`/`mergeItem(at:)` for why this exists
    /// instead of trying to guess pairing automatically. Nothing here is mandatory: a batch
    /// with no bilingual/two-sided cards in it just gets skipped straight through via "完成配對".
    private var pairingStage: some View {
        List {
            Section {
                Text("如果同一張名片的正反面被拍成了兩張獨立照片(常見於正面中文、反面英文的雙語名片),點右邊「合併為上一張的反面」,兩張會併成一張名片。不需要處理的話,直接按下面「完成配對」繼續。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(uiImage: item.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("第 \(index + 1) 張")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.parsed.name.isEmpty ? "(未辨識出姓名)" : item.parsed.name)
                            if item.backImagePath != nil {
                                Text("已合併一張反面照片")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                        }
                        Spacer()
                        if index > 0 {
                            Button("合併為上一張的反面") {
                                mergeItem(at: index)
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                stage = .tagSetup
            } label: {
                Text("完成配對,下一步(\(items.count) 張)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    /// Folds item `index` into item `index - 1` as its back side — called when the user marks
    /// two consecutive batch captures as the front/back of the same physical card in
    /// `pairingStage`. Reuses `OCRService.merge`, exactly what the single-card scan flow
    /// (ScanCardView) uses for front+back, so a paired batch card ends up identical to one
    /// scanned via "掃描一張名片" — same "/"-join convention for fields that disagree, same
    /// phone/email union. Deliberately skips the interactive `FrontBackMergeReviewView` step
    /// ScanCardView shows when front/back disagree: batch mode already trades per-card
    /// interactivity for getting through a whole stack quickly (see the type's doc-comment),
    /// and the merged result is still fully editable moments later in the one-by-one review
    /// form regardless, so nothing here is final until the user actually taps 儲存.
    private func mergeItem(at index: Int) {
        guard items.indices.contains(index), index > 0 else { return }
        var front = items[index - 1]
        let back = items[index]
        front.parsed = OCRService.merge(front: front.parsed, back: back.parsed)
        front.backImagePath = back.frontImagePath
        items[index - 1] = front
        items.remove(at: index)
    }

    private var tagSetupView: some View {
        Form {
            Section("套用標籤到整批 (\(items.count) 張,每張稍後仍可個別調整)") {
                if !allTags.isEmpty {
                    TagChipsRow(tags: allTags, selectedTags: $batchTags)
                } else {
                    Text("還沒有標籤,可以在下面新增一個")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if showingNewTagField {
                    HStack {
                        TextField("新標籤名稱", text: $newTagName)
                        Button("新增") { addBatchTag() }
                            .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } else {
                    Button {
                        showingNewTagField = true
                    } label: {
                        Label("新增標籤", systemImage: "plus")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                currentIndex = 0
                savedCount = 0
                stage = .reviewing
            } label: {
                Text("開始逐張確認(\(items.count) 張)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    private var doneView: some View {
        ContentUnavailableView(
            "批次處理完成",
            systemImage: "checkmark.circle",
            description: Text("已儲存 \(savedCount)/\(items.count) 張名片")
        )
        .safeAreaInset(edge: .bottom) {
            Button {
                dismiss()
            } label: {
                Text("完成")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    private func addBatchTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let tag = Tag(name: trimmed, colorHex: Color.tagPalette.randomElement() ?? "#4A90D9")
        modelContext.insert(tag)
        batchTags.insert(tag)
        newTagName = ""
        showingNewTagField = false
    }

    private func handleScans(_ images: [UIImage]) {
        guard !images.isEmpty else {
            stage = .empty
            return
        }
        items = images.map { BatchScanItem(image: $0) }
        processedCount = 0
        stage = .processing
        recognizeNext(index: 0)
    }

    /// Runs OCR on each captured image one at a time (chained via the completion handler,
    /// always hopping back to the main thread) so mutating the shared `items` array never
    /// races across threads.
    private func recognizeNext(index: Int) {
        guard index < items.count else {
            stage = items.isEmpty ? .empty : .pairing
            return
        }
        let image = items[index].image
        OCRService.recognizeText(in: image) { lines in
            DispatchQueue.main.async {
                items[index].parsed = OCRService.parse(lines: lines)
                items[index].frontImagePath = ImageStorageService.save(image)
                processedCount += 1
                recognizeNext(index: index + 1)
            }
        }
    }

    private func advance(saved: Bool) {
        if saved { savedCount += 1 }
        currentIndex += 1
    }
}
