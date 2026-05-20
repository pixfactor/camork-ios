import Foundation
import SwiftUI

/// Full photo grid for a single session (Plan C Phase 3.4).
///
/// This screen owns gallery-detail loading and photo opening. Name/note editing and
/// share actions are intentionally left as disabled affordances until their planned
/// follow-up tasks wire real sheets.
struct SessionDetailScreen: View {
    @EnvironmentObject private var deps: DependencyContainer

    let session: Session

    @State private var photos: [Photo] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var photoOpenError: String?
    @State private var loadingPhotoID: UUID?
    @State private var detailItem: SessionPhotoDetailItem?
    @State private var sheet: SessionDetailSheet?

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.xs),
        GridItem(.flexible(), spacing: Spacing.xs),
        GridItem(.flexible(), spacing: Spacing.xs)
    ]

    var body: some View {
        content
            .navigationTitle(session.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        sheet = .note
                    } label: {
                        Image(systemName: "note.text")
                    }
                    .disabled(true)
                    .accessibilityLabel(Text("session_detail_edit_note_a11y"))

                    Button {
                        sheet = .share
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(true)
                    .accessibilityLabel(Text("session_detail_share_a11y"))
                }
            }
            .task {
                await refresh()
            }
            .fullScreenCover(item: $detailItem) { item in
                PhotoDetailView(
                    photo: item.photo,
                    data: item.data,
                    memoEditor: PhotoMemoEditor(mediaStorage: deps.mediaStorage),
                    onDismiss: { detailItem = nil }
                )
            }
            .alert(
                "session_detail_photo_open_error_title",
                isPresented: photoOpenErrorBinding,
                presenting: photoOpenError
            ) { _ in
                Button("button_ok", role: .cancel) { photoOpenError = nil }
            } message: { message in
                Text(message)
            }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && photos.isEmpty {
            ProgressView("session_detail_loading")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appBackgroundShield()
        } else if let loadError, photos.isEmpty {
            ContentUnavailableView {
                Text("session_detail_load_error_title")
            } description: {
                Text(loadError)
            } actions: {
                Button("button_retry") {
                    Task { await refresh() }
                }
            }
            .appBackgroundShield()
        } else if photos.isEmpty {
            ContentUnavailableView(
                "session_detail_empty_title",
                systemImage: "photo.on.rectangle",
                description: Text("session_detail_empty_description")
            )
            .appBackgroundShield()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    photoGrid
                }
                .padding(Spacing.md)
            }
            .refreshable {
                await refresh()
            }
            .appBackgroundShield()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label(session.createdAt.formatted(date: .numeric, time: .shortened), systemImage: "calendar")
            if let placeName = session.firstLocation?.placeName, !placeName.isEmpty {
                Label(placeName, systemImage: "mappin.and.ellipse")
            }
            Label(photoCountText, systemImage: "photo.on.rectangle")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var photoGrid: some View {
        LazyVGrid(columns: columns, spacing: Spacing.xs) {
            ForEach(photos, id: \.id) { photo in
                Button {
                    Task { await openPhoto(photo) }
                } label: {
                    ZStack {
                        ThumbnailView(photo: photo)
                        if loadingPhotoID == photo.id {
                            ProgressView()
                                .padding(Spacing.sm)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(loadingPhotoID != nil)
                .accessibilityLabel(Text(photo.capturedAt.formatted(date: .numeric, time: .shortened)))
            }
        }
    }

    private var photoCountText: String {
        let count = photos.count
        if count == 1 {
            return String(localized: "session_card_photo_count_one")
        }
        return String(
            format: String(localized: "session_card_photo_count_other_format"),
            count
        )
    }

    @MainActor
    private func refresh() async {
        isLoading = true
        loadError = nil
        do {
            photos = try await deps.mediaStorage.fetchPhotos(sessionId: session.id)
        } catch {
            loadError = String(describing: error)
        }
        isLoading = false
    }

    @MainActor
    private func openPhoto(_ photo: Photo) async {
        guard loadingPhotoID == nil else { return }
        loadingPhotoID = photo.id
        defer { loadingPhotoID = nil }

        do {
            let data = try await deps.mediaStorage.loadPhotoData(for: photo)
            detailItem = SessionPhotoDetailItem(photo: photo, data: data)
        } catch {
            photoOpenError = String(describing: error)
        }
    }

    private var photoOpenErrorBinding: Binding<Bool> {
        Binding(
            get: { photoOpenError != nil },
            set: { newValue in
                if !newValue { photoOpenError = nil }
            }
        )
    }
}

private enum SessionDetailSheet {
    case note
    case share
}

private struct SessionPhotoDetailItem: Identifiable {
    let photo: Photo
    let data: Data
    var id: UUID { photo.id }
}
