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

    @State private var isFavorite = false
    /// Whether the 追蹤提醒 toggle is on — kept separate from `followUpDate` so the DatePicker
    /// has a concrete non-optional `Date` to bind to while still letting the field as a whole
    /// be "unset" (this toggle off → `followUpDate` saved as nil, cancelling any reminder).
    @State private var hasFollowUp = false
    @State private var followUpDate = Date.now.addingTimeInterval(3 * 24 * 3600)
    /// Set to true if the user turned 追蹤提醒 on but denied (or previously denied) the
    /// notification permission — shown as an inline hint rather than silently saving a
    /// reminder date that will never actually notify anyone.
    @State private var notificationsDenied = false

    @State private var interactions: [InteractionEntry] = []
    @State private var newInteractionText = ""

    @State private var newTagName = ""
    @State private var showingNewTagField = false
    @State private var didLoadInitialState = false

    // Drives the duplicate-warning sheet directly off the candidate itself (`.sheet(item:)`)
    // rather than a separate `Bool` flag alongside it. The previous two-state version
    // (`showingDuplicateWarning = true` + a separately-set `duplicateCandidate`, with the
    // sheet's content closure doing `if let duplicateCandidate { ... }`) is a known SwiftUI
    // footgun: if the sheet's content closure is ever evaluated a beat before the optional's
    // new value has propagated, the `if let` fails and the sheet presents genuinely empty —
    // a blank white sheet that never populates and never dismisses on its own, since nothing
    // in it can be tapped. `.sheet(item:)` can't land in that state: SwiftUI only presents the
    // sheet once the item is non-nil, and the closure receives that value directly, so there's
    // no separate flag that can fall out of sync with it.
    @State private var duplicateCandidate: BusinessCard?

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

            if !isMyCard {
                Section {
                    Toggle("我的最愛", isOn: $isFavorite)
                } footer: {
                    Text("標記後會在名片清單優先顯示,也可以用「只看最愛」篩選。")
                }

                Section {
                    Toggle("設定追蹤提醒", isOn: $hasFollowUp)
                    if hasFollowUp {
                        DatePicker("提醒時間", selection: $followUpDate)
                        if notificationsDenied {
                            Label("尚未允許通知,提醒時間到了不會跳出通知。可以到「設定」App 開啟本 App 的通知權限。", systemImage: "bell.slash")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                } footer: {
                    Text("時間到了會用手機的本機通知提醒你,不需要網路,也不會有任何資料傳出這支手機。")
                }
                .onChange(of: hasFollowUp) { _, newValue in
                    guard newValue else { return }
                    ReminderService.requestAuthorizationIfNeeded { granted in
                        notificationsDenied = !granted
                    }
                }
            }

            Section("標籤") {
                tagPicker
            }

            Section("備註") {
                TextEditor(text: $notes)
                    .frame(minHeight: 100)
            }

            if !isMyCard {
                Section {
                    ForEach(interactions.sorted(by: { $0.date > $1.date })) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.date, format: .dateTime.year().month().day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(entry.text)
                        }
                    }
                    .onDelete { offsets in
                        let sorted = interactions.sorted(by: { $0.date > $1.date })
                        let idsToRemove = Set(offsets.map { sorted[$0].id })
                        interactions.removeAll { idsToRemove.contains($0.id) }
                    }
                    HStack {
                        TextField("例如:在展覽認識、聊了合作案…", text: $newInteractionText, axis: .vertical)
                        Button("新增") { addInteraction() }
                            .disabled(newInteractionText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("互動紀錄")
                } footer: {
                    Text("每一筆都會記錄新增當下的時間,累積成跟這個人的往來紀錄,不會像備註一樣被覆蓋掉。")
                }
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
        .sheet(item: $duplicateCandidate) { duplicate in
            DuplicateWarningView(
                existingCard: duplicate,
                onKeepBoth: {
                    duplicateCandidate = nil
                    save()
                },
                onUpdateExisting: {
                    duplicateCandidate = nil
                    updateExisting(duplicate)
                },
                onCancel: {
                    duplicateCandidate = nil
                }
            )
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

    private func addInteraction() {
        let trimmed = newInteractionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        interactions.append(InteractionEntry(text: trimmed))
        newInteractionText = ""
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
            isFavorite = card.isFavorite
            interactions = card.interactions
            if let existingFollowUp = card.followUpDate {
                hasFollowUp = true
                followUpDate = existingFollowUp
            }
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
        // Either branch above IS the same card `interactions` was loaded from (the existing
        // card being edited, or a brand-new one that had nothing to load) — a straight replace
        // is correct here, unlike `updateExisting` below.
        targetCard.interactions = interactions
        applyExtras(to: targetCard)
        enforceSingleMyCard(keeping: targetCard)
        finish(with: targetCard)
    }

    /// Writes the newer, "extra" fields (最愛/追蹤提醒) onto the card and syncs the follow-up
    /// reminder's local notification to match — shared by both `save()` and `updateExisting()`
    /// so the two saving paths can't drift out of sync with each other. Does NOT touch
    /// `interactions` — see the comment at each call site for why that one needs different
    /// handling depending on whether `card` is the same card the form's `interactions` state
    /// was loaded from. "我的名片" never carries any of these (following up with yourself makes
    /// no sense), so they're forced off for it regardless of whatever the hidden form state holds.
    private func applyExtras(to card: BusinessCard) {
        if isMyCard {
            card.isFavorite = false
            card.followUpDate = nil
            ReminderService.cancel(cardID: card.id)
            return
        }
        card.isFavorite = isFavorite
        if hasFollowUp {
            card.followUpDate = followUpDate
            ReminderService.schedule(cardID: card.id, name: card.name, date: followUpDate)
        } else {
            card.followUpDate = nil
            ReminderService.cancel(cardID: card.id)
        }
    }

    /// Applies the entered fields onto an EXISTING card (the duplicate the user chose to
    /// update) instead of creating a new one. This never overwrites the old record with the
    /// new one — every field is combined, MECE-style, so nothing already on file can be lost
    /// just because this pass didn't happen to re-capture it:
    ///  - Short text fields (name/jobTitle/department/company/website/taxId) keep both
    ///    versions side by side with "/" when they differ (same convention as the front/back
    ///    OCR merge — e.g. a Chinese name and a later-scanned romanized one become "黃 / huang"),
    ///    and skip re-appending a variant that's already present so repeated re-scans of the
    ///    same person don't grow the field forever.
    ///  - Address does the same but with "；", matching the front/back merge's own convention.
    ///  - Phones/emails are unioned and de-duplicated (by the same normalization
    ///    `findDuplicate()` uses to detect them as the same number/address in the first place),
    ///    not replaced — an old number missing from this pass stays on the card.
    ///  - Tags are unioned (old tags like "客戶" stay true even if this pass didn't re-pick them).
    ///  - Photos: the newly-scanned photo becomes the current one (what the thumbnail/vCard
    ///    export use), but the photo it replaces is kept, not deleted — see
    ///    `BusinessCard.additionalFrontImagePaths`/`additionalBackImagePaths`.
    ///  - Notes stays a straight overwrite — unlike the other fields it's free-form prose, not
    ///    a set of discrete facts, so there's no well-defined way to "union" two paragraphs.
    private func updateExisting(_ card: BusinessCard) {
        card.name = OCRService.combineIntoExisting(card.name, name)
        card.jobTitle = OCRService.combineIntoExisting(card.jobTitle, jobTitle)
        card.department = OCRService.combineIntoExisting(card.department, department)
        card.company = OCRService.combineIntoExisting(card.company, company)
        card.website = OCRService.combineIntoExisting(card.website, website)
        card.address = OCRService.combineIntoExisting(card.address, address, separator: "；")
        card.taxId = OCRService.combineIntoExisting(card.taxId, taxId)
        card.notes = notes
        card.phones = mergedContactFields(existing: card.phones, new: phones, key: normalizedDigits)
        card.emails = mergedContactFields(existing: card.emails, new: emails, key: normalizedEmail)
        card.tags = Array(Set(card.tags).union(selectedTags))
        let front = mergedPhoto(existingPrimary: card.frontImagePath, existingOlder: card.additionalFrontImagePaths, newPath: frontImagePath)
        card.frontImagePath = front.primary
        card.additionalFrontImagePaths = front.older
        let back = mergedPhoto(existingPrimary: card.backImagePath, existingOlder: card.additionalBackImagePaths, newPath: backImagePath)
        card.backImagePath = back.primary
        card.additionalBackImagePaths = back.older
        card.isMyCard = isMyCard
        card.dateModified = .now
        // `card` here is the OLD card the duplicate check matched against, not the one
        // `interactions` was loaded from (this form started as a brand-new-card form, so its
        // `interactions` only holds whatever the user typed in THIS session, if anything) —
        // append rather than replace, the same "don't silently lose history" reasoning as
        // everything else in this function, so the old card's interaction history is never
        // overwritten.
        card.interactions += interactions
        applyExtras(to: card)
        enforceSingleMyCard(keeping: card)
        finish(with: card)
    }

    /// Unions an existing card's phones/emails with the newly-entered set, de-duplicating by
    /// whatever normalized `key` the caller passes (digits-only for phones, trimmed+lowercased
    /// for emails — the same normalization `findDuplicate()` uses, so two formattings of the
    /// same number/address collapse into one entry instead of surviving as two).
    private func mergedContactFields(
        existing: [ContactField],
        new: [ContactField],
        key: (ContactField) -> String
    ) -> [ContactField] {
        var seen = Set<String>()
        var result: [ContactField] = []
        for field in existing + new {
            let normalized = key(field)
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(field)
        }
        return result
    }

    /// Folds a newly-scanned photo into an existing card's photo history for one side
    /// (front or back): the new photo becomes the current one; if it's actually different
    /// from what was there, the old one is kept in `older` (deduplicated by filename) rather
    /// than deleted, so re-scanning someone's card never loses the photo that was on file
    /// before. Returns the existing state unchanged when no new photo was captured this pass.
    private func mergedPhoto(
        existingPrimary: String?,
        existingOlder: [String],
        newPath: String?
    ) -> (primary: String?, older: [String]) {
        guard let newPath else { return (existingPrimary, existingOlder) }
        guard let existingPrimary, existingPrimary != newPath else { return (newPath, existingOlder) }
        var older = existingOlder
        if !older.contains(existingPrimary) {
            older.append(existingPrimary)
        }
        return (newPath, older)
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
