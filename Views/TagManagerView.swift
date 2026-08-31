import SwiftUI
import SwiftData

/// Create, rename, recolor, and delete tags. Deleting a tag here just removes the
/// association from every card that had it (cards themselves are untouched).
struct TagManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tag.name) private var tags: [Tag]

    @State private var newTagName = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("新標籤名稱", text: $newTagName)
                    Button("新增") { addTag() }
                        .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section("所有標籤 (\(tags.count))") {
                if tags.isEmpty {
                    Text("還沒有標籤")
                        .foregroundStyle(.secondary)
                }
                ForEach(tags) { tag in
                    TagEditRow(tag: tag)
                }
                .onDelete(perform: deleteTags)
            }
        }
        .navigationTitle("管理標籤")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
    }

    private func addTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let tag = Tag(name: trimmed, colorHex: Color.tagPalette.randomElement() ?? "#4A90D9")
        modelContext.insert(tag)
        newTagName = ""
    }

    private func deleteTags(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(tags[index])
        }
    }
}

private struct TagEditRow: View {
    @Bindable var tag: Tag

    var body: some View {
        HStack {
            Circle()
                .fill(Color(hex: tag.colorHex))
                .frame(width: 20, height: 20)
            TextField("標籤名稱", text: $tag.name)
            Spacer()
            ColorPicker(
                "",
                selection: Binding(
                    get: { Color(hex: tag.colorHex) },
                    set: { newColor in
                        if let hex = newColor.toHex() {
                            tag.colorHex = hex
                        }
                    }
                )
            )
            .labelsHidden()
        }
    }
}
