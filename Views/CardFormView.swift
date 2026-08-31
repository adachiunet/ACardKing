import SwiftUI
import SwiftData
import UIKit

/// Shared add/edit form. Three ways to arrive here:
///  - Manual "+": `existingCard` and `prefilled` are both nil, everything starts blank.
///  - Edit an existing card: `existingCard` is set, fields are loaded from it.
///  - After a scan (single card via ScanCardView, or one item of a batch via BatchScanView):
///    `existingCard` is nil, `prefilled` carries the OCR guess.
///
/// Normally this view is presented as its own sheet and manages its own dismissal. When
/// BatchScanView shows one of these per scanned card in sequence, it instead passes
/// `onSaved`/`onCancelled` so IT controls what happens next (advance to the next card) instead
/// of the whole batch sheet closing after just the first one.
struct CardFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @Query private var allCards: [BusinessCard]

    var existingCard: BusinessCard?
    var prefilled: ParsedCardFields?
    var prefilledFrontImagePath: String?
    var prefilledBackImagePath: String?
    /// Tags to pre-select for a scanned card — e.g. BatchScanView's "套用標籤到整批" selection,
    /// carried forward into each item's form so the user doesn't have to re-pick them per card.
    var prefilledTags: Set<Tag> = []
    /// Starts the "這是我自己的名片" toggle already on — used when opening this form from
    /// MyCardView's "設定我的名片" empty state.
    var startAsMyCard: Bool = false
    /// When set, this view no longer dismisses itself on save/cancel — it calls these instead
    /// and leaves navigation to the caller (BatchScanView's one-card-at-a-time review).
    var onSaved: ((BusinessCard) -> Void)?
    var onCancelled: (() -> Void)?

    @State private var name = ""
    @State private var jobTitle = ""
    @State private var department = ""
    @State private var company = ""
    @State private var phones: [ContactField] = []
    @State private var emails: [ContactField] = []
    @State private var website = ""
    @State private var address = ""
    @State private var taxId = ""
    @State private var notes = ""
    @State private var selectedTags: Set<Tag> = []
    @State private var frontImagePath: String?
    @State private var backImagePath: String?
    @State private var isMyCard = false
    /// The raw OCR text (both sides, when scanned) — shown collapsed under "查看原始辨識文字"
    /// so the user can double-check anything the field parser may have gotten wrong or missed,
    /// without that wall of text cluttering the form itself. Empty (and hidden) for manually
    /// entered or already-saved cards, since only a fresh scan carries this.
    @State private var rawOCRText = ""

    @State private var newTagName = ""
    @State private var showingNewTagField = false
    @State private var didLoadInitialState = false

    @State private var duplicateCandidate: BusinessCard?
    @State private var showingDuplicateWarning = false

    private var isEditing: Bool { existingCard != nil }

    var body: some View {
        Form {
            Section("基本資料") {
                TextField("姓名", text: $name)
                TextField("職稱", text: $jobTitle)
                TextField("部門", text: $department)
                TextField("公司", text: $company)
            }

            Section("電話") {
                ForEach($phones) { $phone in
                    HStack {
                        Picker("", selection: $phone.type) {
                            ForEach(ContactField.FieldType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                        TextField("電話號碼", text: $phone.value)
                            .keyboardType(.phonePad)
                        TextField("分機", text: $phone.ext)
                            .keyboardType(.numberPad)
                            .frame(width: 56)
                    }
                }
                .onDelete { phones.remove(atOffsets: $0) }
                Button {
                    phones.append(ContactField(type: .mobile, value: ""))
                } label: {
                    Label("新增電話", systemImage: "plus.circle")
                }
            }

            Section("Email") {
                ForEach($emails) { $email in
                    HStack {
                        Picker("", selection: $email.type) {
                            ForEach(ContactField.FieldType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                        TextField("Email", text: $email.value)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                    }
                }
                .onDelete { emails.remove(atOffsets: $0) }
                Button {
                    emails.append(ContactField(type: .work, value: ""))
                } label: {
                    Label("新增 Email", systemImage: "plus.circle")
                }
            }

            Section("其他") {
                TextField("網站", text: $website)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                TextField("地址", text: $address, axis: .vertical)
                TextField("統一編號", text: $taxId)
                    .keyboardType(.numberPad)
            }

            Section {
                Toggle("這是我自己的名片", isOn: $isMyCard)
            } footer: {
                Text("標記後可以在「我的名片」畫面用 QR Code 或分享面板分享出去。同一時間只會保留最新標記的一張,標記這張會自動取消其他張的標記。")
            }

            Section("標籤") {
                tagPicker
            }

            Section("備註") {
                TextEditor(text: $notes)
                    .frame(minHeight: 100)
            }

            if frontImagePath != nil || backImagePath != nil {
                Section("名片照片") {
                    HStack {
                        if let path = frontImagePath, let img = ImageStorageService.load(path) {
                            Image(uiImage: img).resizable().scaledToFit().frame(height: 120)
                        }
                        if let path = backImagePath, let img = ImageStorageService.load(path) {
                            Image(uiImage: img).resizable().scaledToFit().frame(height: 120)
                        }
                    }
                }
            }

            if !rawOCRText.isEmpty {
                Section {
                    DisclosureGroup("查看原始辨識文字") {
                        Text(rawOCRText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(isEditing ? "編輯名片" : "新增名片")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    if let onCancelled { onCancelled() } else { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("儲存") { attemptSave() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear(perform: loadInitialStateIfNeeded)
        .sheet(isPresented: $showingDuplicateWarning) {
            if let duplicateCandidate {
                DuplicateWarningView(
                    existingCard: duplicateCandidate,
                    onKeepBoth: {
                        showingDuplicateWarning = false
                        save()
                    },
                    onUpdateExisting: {
                        showingDuplicateWarning = false
                        updateExisting(duplicateCandidate)
                    },
                    onCancel: {
                        showingDuplicateWarning = false
                    }
                )
            }
        }
    }

    private var tagPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if allTags.isEmpty {
                Text("還沒有標籤,可以在下面新增一個")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                TagChipsRow(tags: allTags, selectedTags: $selectedTags)
            }
            if showingNewTagField {
                HStack {
                    TextField("新標籤名稱", text: $newTagName)
                    Button("新增") { addNewTag() }
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

    private func addNewTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let tag = Tag(name: trimmed, colorHex: Color.tagPalette.randomElement() ?? "#4A90D9")
        modelContext.insert(tag)
        selectedTags.insert(tag)
        newTagName = ""
        showingNewTagField = false
    }

    private func loadInitialStateIfNeeded() {
        guard !didLoadInitialState else { return }
        didLoadInitialState = true

        if let card = existingCard {
            name = card.name
            jobTitle = card.jobTitle
            department = card.department
            company = card.company
            phones = card.phones
            emails = card.emails
            website = card.website
            address = card.address
            taxId = card.taxId
            notes = card.notes
            selectedTags = Set(card.tags)
            frontImagePath = card.frontImagePath
            backImagePath = card.backImagePath
            isMyCard = card.isMyCard
        } else if let parsed = prefilled {
            name = parsed.name
            jobTitle = parsed.jobTitle
            department = parsed.department
            company = parsed.company
            phones = parsed.phones
            emails = parsed.emails
            website = parsed.website
            address = parsed.address
            taxId = parsed.taxId
            frontImagePath = prefilledFrontImagePath
            backImagePath = prefilledBackImagePath
            selectedTags = prefilledTags
            rawOCRText = parsed.rawText
            isMyCard = startAsMyCard
        } else {
            isMyCard = startAsMyCard
        }
    }

    // MARK: - Duplicate detection

    /// Matches on phone number (digits only, so formatting differences don't matter), email
    /// (trimmed + lowercased), or an exact name match — any one hit counts, per the three
    /// criteria the user asked this to check. Only ever runs for a brand-new, non-"我的名片"
    /// card: editing an existing card, or saving your own card, isn't "meeting someone again".
    private func findDuplicate() -> BusinessCard? {
        let candidatePhones = Set(phones.map(normalizedDigits).filter { !$0.isEmpty })
        let candidateEmails = Set(emails.map(normalizedEmail).filter { !$0.isEmpty })
        let candidateName = name.trimmingCharacters(in: .whitespaces)

        for card in allCards where !card.isMyCard {
            if !candidatePhones.isEmpty {
                let cardPhones = Set(card.phones.map { normalizedDigits($0.value) })
                if !candidatePhones.isDisjoint(with: cardPhones) { return card }
            }
            if !candidateEmails.isEmpty {
                let cardEmails = Set(card.emails.map { normalizedEmail($0.value) })
                if !candidateEmails.isDisjoint(with: cardEmails) { return card }
            }
            if !candidateName.isEmpty, card.name.trimmingCharacters(in: .whitespaces) == candidateName {
                return card
            }
        }
        return nil
    }

    private func normalizedDigits(_ field: ContactField) -> String { normalizedDigits(field.value) }
    private func normalizedDigits(_ value: String) -> String { value.filter(\.isNumber) }
    private func normalizedEmail(_ field: ContactField) -> String { normalizedEmail(field.value) }
    private func normalizedEmail(_ value: String) -> String { value.trimmingCharacters(in: .whitespaces).lowercased() }

    private func attemptSave() {
        if !isEditing, !isMyCard, let duplicate = findDuplicate() {
            duplicateCandidate = duplicate
            showingDuplicateWarning = true
        } else {
            save()
        }
    }

    // MARK: - Saving

    private func save() {
        let targetCard: BusinessCard
        if let card = existingCard {
            card.name = name
            card.jobTitle = jobTitle
            card.department = department
            card.company = company
            card.phones = phones
            card.emails = emails
            card.website = website
            card.address = address
            card.taxId = taxId
            card.notes = notes
            card.tags = Array(selectedTags)
            card.frontImagePath = frontImagePath
            card.backImagePath = backImagePath
            card.isMyCard = isMyCard
            card.dateModified = .now
            targetCard = card
        } else {
            let card = BusinessCard(
                name: name,
                jobTitle: jobTitle,
                department: department,
                company: company,
                phones: phones,
                emails: emails,
                website: website,
                address: address,
                taxId: taxId,
                notes: notes,
                frontImagePath: frontImagePath,
                backImagePath: backImagePath,
                isMyCard: isMyCard
            )
            card.tags = Array(selectedTags)
            modelContext.insert(card)
            targetCard = card
        }
        enforceSingleMyCard(keeping: targetCard)
        finish(with: targetCard)
    }

    /// Applies the entered fields onto an EXISTING card (the duplicate the user chose to
    /// update) instead of creating a new one. Old tags are kept and merged with any newly
    /// selected ones — a duplicate hit means "same person", so the old tags (e.g. "客戶") are
    /// still true and shouldn't quietly disappear just because this pass didn't re-pick them.
    private func updateExisting(_ card: BusinessCard) {
        card.name = name
        card.jobTitle = jobTitle
        card.department = department
        card.company = company
        card.phones = phones
        card.emails = emails
        card.website = website
        card.address = address
        card.taxId = taxId
        card.notes = notes
        card.tags = Array(Set(card.tags).union(selectedTags))
        if let frontImagePath { card.frontImagePath = frontImagePath }
        if let backImagePath { card.backImagePath = backImagePath }
        card.isMyCard = isMyCard
        card.dateModified = .now
        enforceSingleMyCard(keeping: card)
        finish(with: card)
    }

    private func enforceSingleMyCard(keeping targetCard: BusinessCard) {
        guard isMyCard else { return }
        for other in allCards where other.isMyCard && other.id != targetCard.id {
            other.isMyCard = false
        }
    }

    private func finish(with card: BusinessCard) {
        if let onSaved {
            onSaved(card)
        } else {
            dismiss()
        }
    }
}
