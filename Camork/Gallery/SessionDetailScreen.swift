import Foundation
import SwiftUI

/// Full photo grid for a single session (Plan C Phase 3.4).
///
/// This screen owns gallery-detail loading, name/note editing, and photo opening.
/// Share remains a disabled affordance until the Plan C share phase wires it.
struct SessionDetailScreen: View {
    @EnvironmentObject private var deps: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    let session: Session

    @State private var sessionName: String
    @State private var sessionNote: String?
    @State private var photos: [Photo] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var photoOpenError: String?
    @State private var loadingPhotoID: UUID?
    @State private var detailItem: SessionPhotoDetailItem?
    @State private var sheet: SessionDetailSheet?
    @State private var trashError: String?
    @State private var confirmSessionDelete: Bool = false

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.xs),
        GridItem(.flexible(), spacing: Spacing.xs),
        GridItem(.flexible(), spacing: Spacing.xs)
    ]

    init(session: Session) {
        self.session = session
        self._sessionName = State(initialValue: session.name)
        self._sessionNote = State(initialValue: session.note)
    }

    var body: some View {
        content
            .navigationTitle(sessionName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        sheet = .name
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel(Text("session_detail_edit_name_a11y"))
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        sheet = .note
                    } label: {
                        Image(systemName: "note.text")
                    }
                    .accessibilityLabel(Text("session_detail_edit_note_a11y"))

                    ShareEntryButton(
                        session: session,
                        photos: photos,
                        sharePreparer: deps.sharePreparer
                    )

                    Menu {
                        Button(role: .destructive) {
                            confirmSessionDelete = true
                        } label: {
                            Label("session_detail_delete_session", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(Text("session_detail_overflow_a11y"))
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
                    onDismiss: { detailItem = nil },
                    session: session,
                    sharePreparer: deps.sharePreparer
                )
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .name:
                    SessionNameEditSheet(
                        sessionId: session.id,
                        initialName: sessionName,
                        editor: SessionNameEditor(mediaStorage: deps.mediaStorage)
                    ) { savedName in
                        sessionName = savedName
                    }
                case .note:
                    SessionNoteEditSheet(
                        sessionId: session.id,
                        initialNote: sessionNote,
                        editor: SessionNoteEditor(mediaStorage: deps.mediaStorage)
                    ) { savedNote in
                        sessionNote = savedNote
                    }
                }
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
            .alert(
                "session_detail_trash_error_title",
                isPresented: trashErrorBinding,
                presenting: trashError
            ) { _ in
                Button("button_ok", role: .cancel) { trashError = nil }
            } message: { message in
                Text(message)
            }
            .confirmationDialog(
                Text("session_detail_delete_confirm_title"),
                isPresented: $confirmSessionDelete,
                titleVisibility: .visible
            ) {
                Button("session_detail_delete_session", role: .destructive) {
                    Task { await trashSession() }
                }
                Button("button_cancel", role: .cancel) {}
            } message: {
                Text("session_detail_delete_confirm_message")
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
            if let sessionNote, !sessionNote.isEmpty {
                Text(sessionNote)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.top, Spacing.xs)
            }
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
                .contextMenu {
                    Button(role: .destructive) {
                        Task { await trashPhoto(photo) }
                    } label: {
                        Label("session_detail_move_to_trash", systemImage: "trash")
                    }
                }
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

    @MainActor
    private func trashPhoto(_ photo: Photo) async {
        do {
            try await deps.mediaStorage.softDeletePhoto(id: photo.id)
            await refresh()
        } catch {
            trashError = String(describing: error)
        }
    }

    /// Session 단위 trash 후 화면을 닫아 갤러리로 돌아간다. 실패 시 화면 유지 + alert.
    @MainActor
    private func trashSession() async {
        do {
            try await deps.mediaStorage.softDeleteSession(sessionId: session.id)
            dismiss()
        } catch {
            trashError = String(describing: error)
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

    private var trashErrorBinding: Binding<Bool> {
        Binding(
            get: { trashError != nil },
            set: { newValue in
                if !newValue { trashError = nil }
            }
        )
    }
}

private enum SessionDetailSheet: Identifiable {
    case name
    case note

    var id: String {
        switch self {
        case .name: "name"
        case .note: "note"
        }
    }
}

private struct SessionPhotoDetailItem: Identifiable {
    let photo: Photo
    let data: Data
    var id: UUID { photo.id }
}
