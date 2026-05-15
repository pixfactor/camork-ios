import SwiftUI
import SwiftData

struct FolderPickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Folder.sortOrder) private var folders: [Folder]

    @Binding var selectedFolder: Folder?

    @State private var isCreatingFolder = false
    @State private var newFolderName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(folders) { folder in
                    folderRow(folder)
                }

                if isCreatingFolder {
                    newFolderRow
                }
            }
            .navigationTitle("폴더 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation { isCreatingFolder = true }
                    } label: {
                        Label("새 폴더", systemImage: "folder.badge.plus")
                    }
                    .disabled(isCreatingFolder)
                }
            }
        }
    }

    // MARK: - Folder Row

    @ViewBuilder
    private func folderRow(_ folder: Folder) -> some View {
        Button {
            selectedFolder = folder
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: folder.colorHex))
                    .frame(width: 12, height: 12)

                Text(folder.name)
                    .lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(.primary)

                Spacer()

                if selectedFolder?.id == folder.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - New Folder Row

    private var newFolderRow: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.blue)
                .frame(width: 12, height: 12)

            TextField("폴더 이름", text: $newFolderName)
                .onSubmit { createFolder() }
                .submitLabel(.done)

            Button("추가") { createFolder() }
                .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Actions

    private func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let colors = ["#3B82F6", "#10B981", "#F59E0B", "#EF4444", "#8B5CF6", "#EC4899"]
        let colorHex = colors[Int.random(in: 0..<colors.count)]
        let nextSortOrder = (folders.map(\.sortOrder).max() ?? -1) + 1
        let folder = Folder(name: trimmed, colorHex: colorHex, sortOrder: nextSortOrder)
        modelContext.insert(folder)

        selectedFolder = folder
        withAnimation { isCreatingFolder = false }
        newFolderName = ""
        dismiss()
    }
}
