import SwiftUI
import SwiftData

struct TrashFolderView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<MediaItem> { $0.isDeleted }) 
    private var deletedItems: [MediaItem]

    @State private var itemToDeletePermanently: MediaItem?
    @State private var showingDeleteAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if deletedItems.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(deletedItems) { item in
                            trashRow(item: item)
                        }
                    }
                }
            }
            .navigationTitle("휴지통")
            .alert("영구 삭제", isPresented: $showingDeleteAlert, presenting: itemToDeletePermanently) { item in
                Button("삭제", role: .destructive) { permanentlyDelete(item) }
                Button("취소", role: .cancel) {}
            } message: { item in
                Text("이 항목을 영구 삭제합니다. 복구할 수 없습니다.")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "trash.slash")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("휴지통이 비었습니다")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("삭제된 항목은 30일 동안 보관됩니다")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func trashRow(item: MediaItem) -> some View {
        HStack(spacing: 12) {
            thumbnailView(for: item)
                .frame(width: 48, height: 48)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.memo.isEmpty ? "메모 없음" : item.memo)
                    .font(.subheadline)
                    .lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(.primary)

                Text(capturedDateString(item.capturedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(remainingDays(item.deletedAt))
                    .font(.caption)
                    .foregroundStyle(.red)

                HStack(spacing: 12) {
                    Button {
                        restoreItem(item)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)

                    Button(role: .destructive) {
                        itemToDeletePermanently = item
                        showingDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func thumbnailView(for item: MediaItem) -> some View {
        ThumbnailImageView(
            fileName: item.thumbnailFileName,
            fileURL: FileStorageManager.shared.getThumbnailURL(fileName: item.thumbnailFileName)
        )
    }

    private func capturedDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func remainingDays(_ deletedAt: Date?) -> String {
        guard let deletedAt else { return "" }
        let now = Date()
        let remaining = 30 - Calendar.current.dateComponents([.day], from: deletedAt, to: now).day!
        if remaining <= 0 { return "만료됨" }
        return "D-\(remaining)"
    }

    // MARK: - Actions

    private func restoreItem(_ item: MediaItem) {
        item.isDeleted = false
        item.deletedAt = nil
    }

    private func permanentlyDelete(_ item: MediaItem) {
        Task {
            try? await FileStorageManager.shared.deleteMedia(fileName: item.fileName)
        }
        modelContext.delete(item)
    }
}

// MARK: - Thumbnail Image View

private struct ThumbnailImageView: View {
    let fileName: String
    let fileURL: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(.systemGray5)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .task(id: fileName) {
            image = await ThumbnailCache.shared.thumbnail(for: fileName)
        }
    }
}
