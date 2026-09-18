import SwiftUI

/// Reads a `.vcf` file picked from CardListView's file importer — which may hold one name card
/// or a whole batch exported from someone's phone/CRM — and walks through each parsed vCard
/// using the exact same full-field review form a scan gets (`CardFormView`), one at a time. This
/// is deliberately the same "review before it's saved" and "duplicate-card detection just
/// happens" treatment `BatchScanView` gives a batch of photos — nothing extra needed here for
/// either, since both live in `CardFormView.attemptSave()` already.
struct VCardImportView: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        case loading
        case reviewing
        case empty
    }

    @State private var stage: Stage = .loading
    @State private var parsedCards: [ParsedCardFields] = []
    @State private var currentIndex = 0
    @State private var savedCount = 0

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .loading:
                    ProgressView("讀取中…")
                        .onAppear(perform: load)
                case .reviewing:
                    if currentIndex < parsedCards.count {
                        CardFormView(
                            existingCard: nil,
                            prefilled: parsedCards[currentIndex],
                            prefilledFrontImagePath: nil,
                            prefilledBackImagePath: nil,
                            onSaved: { _ in advance(saved: true) },
                            onCancelled: { advance(saved: false) }
                        )
                        .id(currentIndex)
                    } else {
                        doneView
                    }
                case .empty:
                    ContentUnavailableView(
                        "這個檔案沒有可用的名片資料",
                        systemImage: "person.crop.rectangle.badge.xmark",
                        description: Text("確認選的是 .vcf 格式的聯絡人檔案。")
                    )
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private var navigationTitle: String {
        if case .reviewing = stage, currentIndex < parsedCards.count {
            return "確認第 \(currentIndex + 1)/\(parsedCards.count) 張"
        }
        return "從檔案匯入"
    }

    private var doneView: some View {
        ContentUnavailableView(
            "匯入完成",
            systemImage: "checkmark.circle",
            description: Text("已儲存 \(savedCount)/\(parsedCards.count) 張名片")
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

    /// `url` comes from `.fileImporter`, which hands back a security-scoped URL outside the
    /// app's own sandbox — reading it without bracketing the access calls can silently fail on
    /// a real device even though it works in simulators/previews.
    private func load() {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            stage = .empty
            return
        }
        // Most vCard exports are UTF-8; a small number of older tools still write Latin-1.
        // `String(decoding:as:)` never fails (it replaces anything invalid), so this is only a
        // fallback for the rare non-UTF-8 file rather than a source of silent data loss for the
        // common case.
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let parsed = VCardParser.parseMultiple(text)
        if parsed.isEmpty {
            stage = .empty
        } else {
            parsedCards = parsed
            stage = .reviewing
        }
    }

    private func advance(saved: Bool) {
        if saved { savedCount += 1 }
        currentIndex += 1
    }
}
