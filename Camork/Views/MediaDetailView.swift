import SwiftUI
import SwiftData
import UIKit
import CoreLocation

struct MediaDetailView: View {
    let folder: Folder
    let initialItemID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex: Int = 0
    @State private var showInfoPanel = false
    @State private var showingVideoPlayer = false
    @State private var showingDeleteAlert = false
    @State private var resolvedAddress: String?
    @State private var showingPhotoEditor = false
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var mediaRefreshToken = UUID()

    // Sorted items stable reference
    private var sortedItems: [MediaItem] {
        folder.items.sorted { $0.capturedAt > $1.capturedAt }
    }

    private var currentItem: MediaItem? {
        guard currentIndex < sortedItems.count else { return nil }
        return sortedItems[currentIndex]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            if sortedItems.isEmpty {
                Text("미디어를 찾을 수 없습니다")
                    .foregroundStyle(.secondary)
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(sortedItems.enumerated()), id: \.element.id) { index, item in
                        MediaPageView(item: item, refreshToken: mediaRefreshToken, onPlayVideo: {
                            showingVideoPlayer = true
                        })
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
            }

            if showInfoPanel, let item = currentItem {
                InfoPanel(item: item, resolvedAddress: resolvedAddress)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black.opacity(0.6), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { toolbarContent }
        .onAppear {
            if let idx = sortedItems.firstIndex(where: { $0.id == initialItemID }) {
                currentIndex = idx
            }
        }
        .onChange(of: currentIndex) { _, _ in
            resolvedAddress = nil
            if showInfoPanel { resolveAddress() }
        }
        .onChange(of: showInfoPanel) { _, isShowing in
            if isShowing { resolveAddress() }
        }
        .fullScreenCover(isPresented: $showingVideoPlayer) {
            if let item = currentItem {
                VideoPlayerView(url: FileStorageManager.shared.getMediaURL(fileName: item.fileName))
            }
        }
        .sheet(isPresented: $showingPhotoEditor, onDismiss: {
            mediaRefreshToken = UUID()
        }) {
            if let item = currentItem {
                PhotoEditorView(item: item)
            }
        }
        .shareSheet(isPresented: $showingShareSheet, items: shareItems)
        .alert("미디어 삭제", isPresented: $showingDeleteAlert) {
            Button("삭제", role: .destructive) { deleteCurrentItem() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 항목을 영구 삭제합니다.")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                if let item = currentItem {
                    Button {
                        presentShareSheet(for: item)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.white)
                    }
                    if item.mediaType == .photo {
                        Button {
                            showingPhotoEditor = true
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(.white)
                        }
                    }
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showInfoPanel.toggle()
                    }
                } label: {
                    Image(systemName: showInfoPanel ? "info.circle.fill" : "info.circle")
                        .foregroundStyle(.white)
                }
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Actions

    private func deleteCurrentItem() {
        guard let item = currentItem else { return }
        let fileName = item.fileName
        let newIndex = min(currentIndex, sortedItems.count - 2)
        Task {
            try? await FileStorageManager.shared.deleteMedia(fileName: fileName)
        }
        modelContext.delete(item)
        if sortedItems.count <= 1 {
            dismiss()
        } else {
            currentIndex = max(newIndex, 0)
        }
    }

    private func resolveAddress() {
        guard let item = currentItem,
              let lat = item.latitude,
              let lon = item.longitude else { return }
        let location = CLLocation(latitude: lat, longitude: lon)
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, _ in
            guard let placemark = placemarks?.first else { return }
            let parts = [
                placemark.administrativeArea,
                placemark.locality,
                placemark.name
            ].compactMap { $0 }
            resolvedAddress = parts.joined(separator: " ")
        }
    }

    private func presentShareSheet(for item: MediaItem) {
        let activityItems = ShareManager.shareItem(item)
        guard !activityItems.isEmpty else { return }
        shareItems = activityItems
        showingShareSheet = true
    }
}

// MARK: - Media Page

private struct MediaPageView: View {
    let item: MediaItem
    var refreshToken: UUID
    var onPlayVideo: () -> Void

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1.0
    @GestureState private var magnifyDelta: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var dragDelta: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black
            if item.mediaType == .video {
                videoContent
            } else {
                photoContent
            }
        }
        .task(id: item.fileName + refreshToken.uuidString) {
            image = await ThumbnailCache.shared.thumbnail(for: item.thumbnailFileName)
        }
    }

    private var photoContent: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale * magnifyDelta)
                    .offset(
                        x: offset.width + dragDelta.width,
                        y: offset.height + dragDelta.height
                    )
                    .gesture(magnificationGesture.simultaneously(with: dragGesture))
                    .onTapGesture(count: 2) { resetZoom() }
            } else {
                ProgressView().tint(.white)
            }
        }
    }

    private var videoContent: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .overlay(Color.black.opacity(0.3))
            }
            Button(action: onPlayVideo) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.white)
                    .shadow(radius: 8)
            }
        }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($magnifyDelta) { value, state, _ in state = value }
            .onEnded { value in
                let newScale = (scale * value).clamped(to: 1.0...6.0)
                scale = newScale
                if newScale == 1.0 { offset = .zero }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($dragDelta) { value, state, _ in
                guard scale > 1.0 else { return }
                state = value.translation
            }
            .onEnded { value in
                guard scale > 1.0 else { return }
                offset = CGSize(
                    width: offset.width + value.translation.width,
                    height: offset.height + value.translation.height
                )
            }
    }

    private func resetZoom() {
        withAnimation(.spring(duration: 0.3)) {
            scale = 1.0
            offset = .zero
        }
    }
}

// MARK: - Info Panel

private struct InfoPanel: View {
    @Bindable var item: MediaItem
    let resolvedAddress: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            handle

            Group {
                infoRow(
                    icon: "calendar",
                    title: "촬영 일시",
                    value: DateFormatter.sectionHeader.string(from: item.capturedAt)
                        + " " + DateFormatter.timeOnly.string(from: item.capturedAt)
                )

                if item.latitude != nil || item.longitude != nil {
                    infoRow(
                        icon: "location",
                        title: "위치",
                        value: resolvedAddress ?? locationString
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("메모", systemImage: "note.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("메모 추가...", text: $item.memo, axis: .vertical)
                        .font(.subheadline)
                        .lineLimit(3...6)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .ignoresSafeArea(edges: .bottom)
    }

    private var handle: some View {
        Capsule()
            .fill(Color(.systemGray4))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
            }
        }
    }

    private var locationString: String {
        guard let lat = item.latitude, let lon = item.longitude else { return "" }
        return String(format: "%.5f, %.5f", lat, lon)
    }
}

// MARK: - Comparable clamped

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
