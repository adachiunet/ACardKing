import SwiftUI
import SwiftData
import UIKit

/// One item in a batch-scan session: one captured card-front photo plus its OCR guess, held
/// in memory until the user reaches (and confirms) its turn in the one-at-a-time review —
/// nothing is written to SwiftData before that.
private struct BatchScanItem: Identifiable {
    let id = UUID()
    var image: UIImage
    var frontImagePath: String?
    var parsed = ParsedCardFields()
}

/// Batch-add flow: gets a whole stack of card-front photos in one go — either freshly captured
/// via the system document scanner's native multi-page capture, or picked from photos already
/// sitting in the library (e.g. business-card photos someone sent over Messages/LINE) — runs
/// OCR on each, lets the user pick a shared set of tags to apply to the whole batch, then walks
/// through the cards ONE AT A TIME using the exact same full-field review form as a single scan
/// (CardFormView), so every field can be checked/fixed and nothing gets saved without an
/// explicit "儲存" tap per card. Every picked/scanned image becomes its own card (one photo =
/// one card, front only) — this deliberately does NOT try to guess that image N and N+1 are
/// the front/back of the same card, since neither capture order nor photo-library selection
/// order is a reliable signal for that; a card that needs both sides goes through the
/// single-card scan flow (ScanCardView) instead.
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
                case .tagSetup:
                    tagSetupView
                case .reviewing:
                    if currentIndex < items.count {
                        CardFormView(
                            existingCard: nil,
                            prefilled: items[currentIndex].parsed,
                            prefilledFrontImagePath: items[currentIndex].frontImagePath,
                            prefilledBackImagePath: nil,
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
            stage = items.isEmpty ? .empty : .tagSetup
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
