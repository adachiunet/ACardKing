import SwiftUI
import SwiftData
import UIKit

/// Read-only detail screen for one card, with edit / export-this-card / delete in the menu.
struct CardDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var card: BusinessCard

    @State private var showingEdit = false
    @State private var exportFile: ExportFile?

    var body: some View {
        List {
            headerSection

            if !card.phones.isEmpty {
                Section("電話") {
                    ForEach(card.phones) { phone in
                        LabeledContent(
                            phone.type.displayName,
                            value: phone.ext.isEmpty ? phone.value : "\(phone.value) 分機\(phone.ext)"
                        )
                    }
                }
            }
            if !card.emails.isEmpty {
                Section("Email") {
                    ForEach(card.emails) { email in
                        LabeledContent(email.type.displayName, value: email.value)
                    }
                }
            }
            if !card.website.isEmpty || !card.address.isEmpty || !card.taxId.isEmpty {
                Section("其他") {
                    if !card.website.isEmpty { LabeledContent("網站", value: card.website) }
                    if !card.address.isEmpty { LabeledContent("地址", value: card.address) }
                    if !card.taxId.isEmpty { LabeledContent("統一編號", value: card.taxId) }
                }
            }
            if !card.tags.isEmpty {
                Section("標籤") {
                    HStack {
                        ForEach(card.tags) { tag in TagChip(tag: tag) }
                    }
                }
            }
            if !card.notes.isEmpty {
                Section("備註") {
                    Text(card.notes)
                }
            }
            if card.frontImagePath != nil || card.backImagePath != nil {
                Section("名片照片") {
                    HStack {
                        if let path = card.frontImagePath, let img = ImageStorageService.load(path) {
                            Image(uiImage: img).resizable().scaledToFit()
                        }
                        if let path = card.backImagePath, let img = ImageStorageService.load(path) {
                            Image(uiImage: img).resizable().scaledToFit()
                        }
                    }
                }
            }
        }
        .navigationTitle(card.name.isEmpty ? "名片" : card.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingEdit = true
                    } label: {
                        Label("編輯", systemImage: "square.and.pencil")
                    }
                    Button {
                        exportThisCard()
                    } label: {
                        Label("匯出這張名片", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive) {
                        deleteCard()
                    } label: {
                        Label("刪除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                CardFormView(existingCard: card, prefilled: nil, prefilledFrontImagePath: nil, prefilledBackImagePath: nil)
            }
        }
        .sheet(item: $exportFile) { file in
            ShareSheet(items: file.items)
        }
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: 16) {
                if let path = card.frontImagePath, let img = ImageStorageService.load(path) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                }
                VStack(alignment: .leading) {
                    Text(card.name.isEmpty ? "未命名" : card.name)
                        .font(.title2).bold()
                    let subtitle = [card.jobTitle, card.department, card.company]
                        .filter { !$0.isEmpty }.joined(separator: " · ")
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Exports this one card as a vCard (with the front photo already embedded inside it)
    /// *and* attaches the original front/back photo files alongside it in the same share
    /// sheet action, so the full-resolution scans are just as exportable as the text/contact
    /// data — AirDrop, Files, Messages etc. all receive the .vcf plus each photo as its own
    /// file, not just what's embedded in the vCard.
    private func exportThisCard() {
        guard let vcardURL = ExportService.writeVCardFile(
            cards: [card],
            filename: "\(card.name.isEmpty ? "名片" : card.name).vcf"
        ) else { return }

        var items: [Any] = [vcardURL]
        if let frontURL = ImageStorageService.fileURL(for: card.frontImagePath) { items.append(frontURL) }
        if let backURL = ImageStorageService.fileURL(for: card.backImagePath) { items.append(backURL) }
        exportFile = ExportFile(items: items)
    }

    private func deleteCard() {
        ImageStorageService.delete(card.frontImagePath)
        ImageStorageService.delete(card.backImagePath)
        modelContext.delete(card)
        dismiss()
    }
}
