import SwiftUI
import SwiftData

private struct ItemFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct FolderDetailView: View {
    let folder: Folder

    @Environment(\.modelContext) private var modelContext
    @State private var isSelectMode = false
    @State private var selectedIDs = Set<UUID>()
    @State private var showingEditFolder = false
    @State private var showingMoveSheet = false
    @State private var showingDeleteAlert = false
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var itemFrames: [UUID: CGRect] = [:]

    private let gridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    private var groupedItems: [(date: Date, items: [MediaItem])] {
        let sorted = folder.items.sorted { $0.capturedAt > $1.capturedAt }
        let grouped = Dictionary(grouping: sorted) {
            Calendar.current.startOfDay(for: $0.capturedAt)
        }
        return grouped
            .map { (date: $0.key, items: $0.value) }
            .sorted { $0.date > $1.date }
    }

    private var selectedItems: [MediaItem] {
        folder.items.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mainContent
            if isSelectMode && !selectedIDs.isEmpty {
                selectionActionBar
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSelectMode)
        .toolbar { toolbarContent }
        .navigationDestination(for: MediaItem.self) { item in
            MediaDetailView(folder: folder, initialItemID: item.id)
        }
        .sheet(isPresented: $showingEditFolder) {
            FolderEditView(folder: folder)
        }
        .sheet(isPresented: $showingMoveSheet) {
            MoveToFolderView(
                currentFolder: folder,
                selectedItems: selectedItems
            ) {
                exitSelectMode()
            }
        }
        .shareSheet(isPresented: $showingShareSheet, items: shareItems)
        .alert("미디어 삭제", isPresented: $showingDeleteAlert) {
            Button("삭제", role: .destructive) { deleteSelectedItems() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("선택한 \(selectedIDs.count)개 항목을 영구 삭제합니다.")
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if folder.items.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(groupedItems, id: \.date) { group in
                        Section {
                            LazyVGrid(columns: gridColumns, spacing: 2) {
                                ForEach(group.items) { item in
                                    gridCell(for: item)
                                }
                            }
                        } header: {
                            sectionHeader(for: group.date)
                        }
                    }
                }
                .padding(.bottom, isSelectMode ? 80 : 0)
            }
            .onPreferenceChange(ItemFramePreferenceKey.self) { frames in
                itemFrames = frames
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .global)
                    .onChanged { value in
                        guard isSelectMode else { return }
                        selectItemAt(location: value.location)
                    }
            )
        }
    }

    @ViewBuilder
    private func gridCell(for item: MediaItem) -> some View {
        let isSelected = selectedIDs.contains(item.id)
        if isSelectMode {
            MediaGridItem(item: item, isSelectMode: true, isSelected: isSelected)
                .onTapGesture { toggleSelection(item) }
                .background(itemFrameReader(for: item.id))
        } else {
            NavigationLink(value: item) {
                MediaGridItem(item: item)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        withAnimation { isSelectMode = true }
                        selectedIDs.insert(item.id)
                    }
            )
            .background(itemFrameReader(for: item.id))
        }
    }

    private func sectionHeader(for date: Date) -> some View {
        Text(date.relativeDateString())
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("아직 사진이 없습니다")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("카메라로 촬영하면 이 폴더에 저장됩니다")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelectMode {
            ToolbarItem(placement: .topBarLeading) {
                Button("취소") { exitSelectMode() }
            }
            ToolbarItem(placement: .principal) {
                Text(selectedIDs.isEmpty ? "항목 선택" : "\(selectedIDs.count)개 선택됨")
                    .fontWeight(.semibold)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(selectedIDs.count == folder.items.count ? "전체 해제" : "전체 선택") {
                    toggleSelectAll()
                }
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !folder.items.isEmpty {
                        Button {
                            presentShareSheet(for: folder.items)
                        } label: {
                            Label("폴더 전체 공유", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button {
                        showingEditFolder = true
                    } label: {
                        Label("폴더 편집", systemImage: "pencil")
                    }
                    Button {
                        withAnimation { isSelectMode = true }
                    } label: {
                        Label("선택", systemImage: "checkmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: - Selection Action Bar

    private var selectionActionBar: some View {
        HStack(spacing: 0) {
            actionBarButton(title: "공유", icon: "square.and.arrow.up") {
                presentShareSheet(for: selectedItems)
            }
            Divider().frame(height: 30)
            actionBarButton(title: "이동", icon: "folder") {
                showingMoveSheet = true
            }
            Divider().frame(height: 30)
            actionBarButton(title: "삭제", icon: "trash", role: .destructive) {
                showingDeleteAlert = true
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func actionBarButton(
        title: String,
        icon: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18))
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(role == .destructive ? .red : .primary)
    }

    // MARK: - Helpers

    private func itemFrameReader(for id: UUID) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: ItemFramePreferenceKey.self,
                value: [id: geo.frame(in: .global)]
            )
        }
    }

    private func selectItemAt(location: CGPoint) {
        for (id, frame) in itemFrames {
            if frame.contains(location) {
                selectedIDs.insert(id)
                break
            }
        }
    }

    private func toggleSelection(_ item: MediaItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    private func toggleSelectAll() {
        if selectedIDs.count == folder.items.count {
            selectedIDs.removeAll()
        } else {
            selectedIDs = Set(folder.items.map(\.id))
        }
    }

    private func exitSelectMode() {
        withAnimation { isSelectMode = false }
        selectedIDs.removeAll()
    }

    private func deleteSelectedItems() {
        let toDelete = folder.items.filter { selectedIDs.contains($0.id) }
        let fileNames = toDelete.map(\.fileName)
        Task {
            for name in fileNames {
                try? await FileStorageManager.shared.deleteMedia(fileName: name)
            }
        }
        for item in toDelete { modelContext.delete(item) }
        exitSelectMode()
    }

    private func presentShareSheet(for items: [MediaItem]) {
        let activityItems = ShareManager.shareItems(items)
        guard !activityItems.isEmpty else { return }
        shareItems = activityItems
        showingShareSheet = true
    }
}
