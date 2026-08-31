import SwiftUI

/// Shown between "OCR finished" and the normal review form, ONLY when the front and back
/// photos' OCR guesses actually disagree on something (see `OCRService.divergentFields`) —
/// most often a Chinese/English bilingual card. Previously the two sides were silently joined
/// with " / " with no way to say otherwise; this makes that an explicit choice per field
/// instead of a silent guess.
struct FrontBackMergeReviewView: View {
    let front: ParsedCardFields
    let back: ParsedCardFields
    var onContinue: (ParsedCardFields) -> Void

    enum FieldChoice: String, CaseIterable {
        case both = "都要(合併)"
        case frontOnly = "只用正面"
        case backOnly = "只用反面"
    }

    private struct MergeField: Identifiable {
        let id: String
        let label: String
        let frontValue: String
        let backValue: String
    }

    private var mergeFields: [MergeField] {
        var result: [MergeField] = []
        func addIfDifferent(_ id: String, _ label: String, _ frontValue: String, _ backValue: String) {
            let f = frontValue.trimmingCharacters(in: .whitespaces)
            let b = backValue.trimmingCharacters(in: .whitespaces)
            guard !f.isEmpty, !b.isEmpty, f != b else { return }
            result.append(MergeField(id: id, label: label, frontValue: f, backValue: b))
        }
        addIfDifferent("name", "姓名", front.name, back.name)
        addIfDifferent("jobTitle", "職稱", front.jobTitle, back.jobTitle)
        addIfDifferent("company", "公司", front.company, back.company)
        addIfDifferent("website", "網站", front.website, back.website)
        addIfDifferent("address", "地址", front.address, back.address)
        return result
    }

    @State private var choices: [String: FieldChoice] = [:]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(
                        "正面跟反面辨識出不一樣的內容,通常是中英文對照。每一項選好要保留正面、反面,還是兩個都要,再繼續。",
                        systemImage: "rectangle.on.rectangle.angled"
                    )
                    .foregroundStyle(.secondary)
                }

                ForEach(mergeFields) { field in
                    Section(field.label) {
                        LabeledContent("正面", value: field.frontValue)
                        LabeledContent("反面", value: field.backValue)
                        Picker("要保留的內容", selection: binding(for: field.id)) {
                            ForEach(FieldChoice.allCases, id: \.self) { choice in
                                Text(choice.rawValue).tag(choice)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section {
                    Button("繼續") {
                        onContinue(resolvedFields())
                    }
                } footer: {
                    Text("下一步還會看到完整表單,這裡的選擇之後也可以再修改。")
                }
            }
            .navigationTitle("正反面資料合併")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }

    private func binding(for id: String) -> Binding<FieldChoice> {
        Binding(
            get: { choices[id] ?? .both },
            set: { choices[id] = $0 }
        )
    }

    private func resolvedFields() -> ParsedCardFields {
        var merged = OCRService.merge(front: front, back: back)
        for field in mergeFields {
            let choice = choices[field.id] ?? .both
            let resolvedValue: String
            switch choice {
            case .both:
                continue // OCRService.merge already combined this one with " / " or "；"
            case .frontOnly:
                resolvedValue = field.frontValue
            case .backOnly:
                resolvedValue = field.backValue
            }
            switch field.id {
            case "name": merged.name = resolvedValue
            case "jobTitle": merged.jobTitle = resolvedValue
            case "company": merged.company = resolvedValue
            case "website": merged.website = resolvedValue
            case "address": merged.address = resolvedValue
            default: break
            }
        }
        return merged
    }
}
