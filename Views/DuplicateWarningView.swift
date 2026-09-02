import SwiftUI

/// Shown from CardFormView right before a NEW card is actually saved, when the phone number,
/// email, or exact name being entered matches a card that already exists. The point isn't to
/// block the save — it's to surface the relationship history (when this person was first
/// added, what tags/notes are already on record) so the user can recognize "oh, I already met
/// them" before deciding what to do about it.
struct DuplicateWarningView: View {
    let existingCard: BusinessCard
    var onKeepBoth: () -> Void
    var onUpdateExisting: () -> Void
    var onCancel: () -> Void

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("已經有一張很像的名片,可能是同一個人", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                Section("既有名片(你跟這個人的紀錄)") {
                    LabeledContent("姓名", value: existingCard.name.isEmpty ? "(未命名)" : existingCard.name)
                    if !existingCard.company.isEmpty {
                        LabeledContent("公司", value: existingCard.company)
                    }
                    if !existingCard.jobTitle.isEmpty {
                        LabeledContent("職稱", value: existingCard.jobTitle)
                    }
                    ForEach(existingCard.phones) { phone in
                        LabeledContent(phone.type.displayName, value: phone.value)
                    }
                    ForEach(existingCard.emails) { email in
                        LabeledContent(email.type.displayName, value: email.value)
                    }
                    LabeledContent("何時加入", value: dateFormatter.string(from: existingCard.dateAdded))
                    LabeledContent("最後更新", value: dateFormatter.string(from: existingCard.dateModified))
                    if !existingCard.tags.isEmpty {
                        LabeledContent("標籤", value: existingCard.tags.map(\.name).joined(separator: "、"))
                    }
                    if !existingCard.notes.isEmpty {
                        LabeledContent("備註", value: existingCard.notes)
                    }
                }

                Section {
                    Button {
                        onUpdateExisting()
                    } label: {
                        Label("更新舊名片(合併新舊資料)", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button {
                        onKeepBoth()
                    } label: {
                        Label("仍然新增為另一張名片", systemImage: "plus.rectangle.on.rectangle")
                    }
                } footer: {
                    Text("「更新舊名片」不會覆蓋掉舊資料:姓名、公司等欄位如果新舊不同,會用「/」合併保留兩者(地址用「；」);電話、Email 會兩邊都留著並自動去除重複;標籤是聯集。如果這次掃到新的照片,舊照片會保留在「更早的照片」,不會被取代或刪除。備註仍然是用這次輸入的內容取代。")
                }

                Section {
                    Button("取消,回去修改", role: .cancel) {
                        onCancel()
                    }
                }
            }
            .navigationTitle("發現重複名片")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }
}
