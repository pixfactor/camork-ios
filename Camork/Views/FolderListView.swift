import SwiftUI
import SwiftData
import UIKit

struct FolderListView: View {
    @Query(sort: \Folder.sortOrder) private var folders: [Folder]
    @Environment(\.modelContext) private var modelContext

    @State private var showingAddFolder = false
    @State private var folderToEdit: Folder?
    @State private var folderToDelete: Folder?
    @State private var showingDeleteAlert = false
    @State private var draggedFolder: Folder?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if folders.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(folders) { folder in
                                NavigationLink(value: folder) {
                                    FolderCard(folder: folder)
                                }
                                .buttonStyle(.plain)
                                .scaleEffect(draggedFolder?.id == folder.id ? 1.05 : 1.0)
                                .shadow(
                                    color: draggedFolder?.id == folder.id ? .black.opacity(0.25) : .clear,
                                    radius: 10, y: 4
                                )
                                .opacity(draggedFolder?.id == folder.id ? 0.75 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: draggedFolder?.id)
                                .onDrag {
                                    draggedFolder = folder
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    return NSItemProvider(object: folder.id.uuidString as NSString)
                                }
                                .onDrop(of: [.text], delegate: FolderDropDelegate(
                                    targetFolder: folder,
                                    folders: folders,
                                    draggedFolder: $draggedFolder,
                                    modelContext: modelContext
                                ))
                                .contextMenu {
                                    Button {
                                        folderToEdit = folder
                                    } label: {
                                        Label("편집", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        folderToDelete = folder
                                        showingDeleteAlert = true
                                    } label: {
                                        Label("삭제", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Camork")
            .navigationDestination(for: Folder.self) { folder in
                FolderDetailView(folder: folder)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(destination: TrashFolderView()) {
                        Image(systemName: "trash")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddFolder = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddFolder) {
                FolderEditView()
            }
            .sheet(item: $folderToEdit) { folder in
                FolderEditView(folder: folder)
            }
            .alert("폴더 삭제", isPresented: $showingDeleteAlert, presenting: folderToDelete) { folder in
                Button("삭제", role: .destructive) { deleteFolder(folder) }
                Button("취소", role: .cancel) {}
            } message: { folder in
                Text("'\(folder.name)' 폴더와 모든 미디어를 휴지통으로 이동합니다.")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("폴더를 만들어 업무 사진을 정리하세요")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button("새 폴더 만들기") {
                showingAddFolder = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func deleteFolder(_ folder: Folder) {
        for item in folder.items {
            item.isDeleted = true
            item.deletedAt = Date()
            item.folder = nil
        }
        modelContext.delete(folder)
    }
}

// MARK: - Drag & Drop Delegate

private struct FolderDropDelegate: DropDelegate {
    let targetFolder: Folder
    let folders: [Folder]
    @Binding var draggedFolder: Folder?
    let modelContext: ModelContext

    func performDrop(info: DropInfo) -> Bool {
        draggedFolder = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedFolder,
              dragged.id != targetFolder.id,
              let fromIndex = folders.firstIndex(where: { $0.id == dragged.id }),
              let toIndex = folders.firstIndex(where: { $0.id == targetFolder.id })
        else { return }

        var reordered = folders
        reordered.move(
            fromOffsets: IndexSet(integer: fromIndex),
            toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
        )
        for (index, folder) in reordered.enumerated() {
            folder.sortOrder = index
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Folder Card

private struct FolderCard: View {
    let folder: Folder
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnailArea
            infoArea
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.07), radius: 5, y: 2)
        .task(id: folder.latestThumbnail) {
            guard let fileName = folder.latestThumbnail else {
                thumbnail = nil
                return
            }
            thumbnail = await ThumbnailCache.shared.thumbnail(for: fileName)
        }
    }

    private var thumbnailArea: some View {
        ZStack {
            Color(hex: folder.colorHex).opacity(0.18)
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "folder.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color(hex: folder.colorHex))
            }
        }
        .frame(height: 120)
        .clipped()
    }

    private var infoArea: some View {
        HStack(spacing: 6) {
            FolderColorIndicator(colorHex: folder.colorHex, size: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(.primary)
                Text("\(folder.itemCount)개")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }
}
