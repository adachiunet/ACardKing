import SwiftUI
import SwiftData

/// "我的名片" — the user's own card, flagged separately from everyone else's contacts
/// (`BusinessCard.isMyCard`) so it can be shown here for quick, fully-offline sharing: the
/// front photo itself, and a QR code (a vCard, generated on-device via QRCodeService) that
/// someone else can capture with their own phone's camera to pull in the contact info.
///
/// Bluetooth/NFC business-card "beaming" isn't something a third-party iOS app is allowed to
/// drive — Core Bluetooth has no generic peer-to-peer payload exchange API for this, and
/// Core NFC can only READ tags, not host a writable one continuously in the background — so
/// the system share sheet (AirDrop, LINE, Messages, Mail, saving to Photos, …) plus this QR
/// code are the realistic, fully-offline equivalent.
struct MyCardView: View {
    @Query private var allCards: [BusinessCard]

    @State private var showingForm = false
    @State private var shareFile: ExportFile?

    private var myCard: BusinessCard? { allCards.first(where: \.isMyCard) }

    var body: some View {
        NavigationStack {
            Group {
                if let card = myCard {
                    detail(for: card)
                } else {
                    emptyState
                }
            }
            .navigationTitle("我的名片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if myCard != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("編輯") { showingForm = true }
                    }
                }
            }
            .sheet(isPresented: $showingForm) {
                NavigationStack {
                    CardFormView(
                        existingCard: myCard,
                        prefilled: nil,
                        prefilledFrontImagePath: nil,
                        prefilledBackImagePath: nil,
                        startAsMyCard: true
                    )
                }
            }
            .sheet(item: $shareFile) { file in
                ShareSheet(items: file.items)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("還沒有設定我的名片", systemImage: "person.crop.rectangle")
        } description: {
            Text("設定後,就能用大頭照 + QR Code 快速把名片分享給別人,不用每次都手動輸入。")
        } actions: {
            Button("設定我的名片") { showingForm = true }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func detail(for card: BusinessCard) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                cardPreview(for: card)

                if let qr = QRCodeService.generate(from: ExportService.vCard(for: card)) {
                    VStack(spacing: 8) {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220, height: 220)
                            .padding(12)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        Text("讓對方用相機掃一下,直接帶入聯絡資訊")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 6) {
                    Button {
                        share(card)
                    } label: {
                        Label("分享名片", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Text("藍牙/NFC 無法由一般 App 直接控制,這裡改用系統分享面板 — AirDrop、LINE、訊息、Mail、存到照片 都在裡面")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func cardPreview(for card: BusinessCard) -> some View {
        if let path = card.frontImagePath, let img = ImageStorageService.load(path) {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        } else {
            VStack(spacing: 6) {
                Text(card.name.isEmpty ? "(未命名)" : card.name)
                    .font(.title2.bold())
                if !card.company.isEmpty {
                    Text(card.company)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    /// The front photo (if there is one) plus a .vcf file, same as any other single-card
    /// vCard export — LINE, AirDrop, Mail etc. in the share sheet can all take either.
    private func share(_ card: BusinessCard) {
        var items: [Any] = []
        if let path = card.frontImagePath, let img = ImageStorageService.load(path) {
            items.append(img)
        }
        if let url = ExportService.writeVCardFile(cards: [card], filename: "我的名片.vcf") {
            items.append(url)
        }
        guard !items.isEmpty else { return }
        shareFile = ExportFile(items: items)
    }
}
