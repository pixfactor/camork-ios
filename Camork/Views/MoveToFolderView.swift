import SwiftUI
import SwiftData

struct MoveToFolderView: View {
    let currentFolder: Folder
    let selectedItems: [MediaItem]
    var onMoved: (() -> Void)?

    @Query(sort: \Folder.sortOrder) private var allFolders: [Folder]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var availableFolders: [Folder] {
        allFolders.filter { $0.id != currentFolder.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if availableFolders.isEmpty {
                    emptyState
                } else {
                    List(availableFolders) { folder in
                        Button {
                            moveItems(to: folder)
                        } label: {
                            HStack(spacing: 12) {
                                FolderColorIndicator(colorHex: folder.colorHex, size: 14)
                                Text(folder.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(folder.itemCount)개")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("폴더 이동")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("이동할 수 있는 다른 폴더가 없습니다")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func moveItems(to targetFolder: Folder) {
        for item in selectedItems {
            item.folder = targetFolder
        }
        onMoved?()
        dismiss()
    }
}
