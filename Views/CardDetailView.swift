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
    @State private var newInteractionText = ""

    var body: some View {
        List {
            headerSection

            if !card.isMyCard {
                Section {
                    if let followUpDate = card.followUpDate {
                        LabeledContent("追蹤提醒", value: followUpDate.formatted(date: .abbreviated, time: .shortened))
                        Button("取消提醒", role: .destructive) { cancelFollowUp() }
                    } else {
                        Text("還沒設定追蹤提醒,可以到「編輯」裡設定。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

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
            if !card.isMyCard {
                Section("互動紀錄") {
                    ForEach(card.interactions.sorted(by: { $0.date > $1.date })) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.date, format: .dateTime.year().month().day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(entry.text)
                        }
                    }
                    .onDelete(perform: deleteInteractions)
                    HStack {
                        TextField("快速新增一筆紀錄…", text: $newInteractionText, axis: .vertical)
                        Button("新增") { addInteraction() }
                            .disabled(newInteractionText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
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

            // Older front/back photos that a duplicate-card merge bumped out of the current
            // slot above (see BusinessCard.additionalFrontImagePaths/additionalBackImagePaths,
            // CardFormView.updateExisting()) — collapsed by default since most cards never
            // accumulate any, but never deleted, so they need to be reachable somewhere.
            let olderPhotoPaths = card.additionalFrontImagePaths + card.additionalBackImagePaths
            if !olderPhotoPaths.isEmpty {
                Section {
                    DisclosureGroup("更早的照片(\(olderPhotoPaths.count))") {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(olderPhotoPaths, id: \.self) { path in
                                    if let img = ImageStorageService.load(path) {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(height: 100)
                                    }
                                }
                            }
                        }
                    }
                } footer: {
                    Text("重複更新這張名片、又掃到不同的照片時,舊照片會留在這裡,不會被刪除。")
                }
            }
        }
        .navigationTitle(card.name.isEmpty ? "名片" : card.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !card.isMyCard {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        card.isFavorite.toggle()
                    } label: {
                        Image(systemName: card.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(card.isFavorite ? .yellow : .primary)
                    }
                }
            }
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

    /// Soft-deletes — the record (and its photos) stay on disk, just flagged and hidden from
    /// the main list, so a mis-tap can be undone from 垃圾桶 (TrashView). `TrashService` is
    /// what actually removes the photo files and the record for good, once it's been in the
    /// trash long enough (or the user explicitly empties it there).
    private func deleteCard() {
        card.isDeleted = true
        card.deletedAt = .now
        ReminderService.cancel(cardID: card.id)
        dismiss()
    }

    private func cancelFollowUp() {
        card.followUpDate = nil
        ReminderService.cancel(cardID: card.id)
    }

    private func addInteraction() {
        let trimmed = newInteractionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        card.interactions.append(InteractionEntry(text: trimmed))
        newInteractionText = ""
    }

    private func deleteInteractions(at offsets: IndexSet) {
        let sorted = card.interactions.sorted(by: { $0.date > $1.date })
        let idsToRemove = Set(offsets.map { sorted[$0].id })
        card.interactions.removeAll { idsToRemove.contains($0.id) }
    }
}
