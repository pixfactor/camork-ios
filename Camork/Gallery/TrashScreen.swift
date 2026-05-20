import SwiftUI

/// Trash viewer (Plan E Batch E1.c).
///
/// 책임:
/// - `MediaStorage.fetchDeletedSessions` + `fetchDeletedPhotos`로 휴지통 항목 표시.
/// - 세션 / 사진 두 섹션. swipe action으로 restore / purge 호출.
/// - 빈 상태 / 로드 오류 / 진행 중 상태 분기는 GalleryScreen 패턴을 따른다.
/// - viewer가 존재해야 비로소 Plan E E2에서 delete UI를 노출할 수 있다 — 항목 stranding 방지.
struct TrashScreen: View {
    @EnvironmentObject private var deps: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    @State private var sessions: [Session] = []
    @State private var photos: [Photo] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var pendingPurge: PendingPurge?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("trash_title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("button_close") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(isLoading)
                        .accessibilityLabel(Text("gallery_refresh_a11y"))
                    }
                }
        }
        .task {
            await refresh()
        }
        .alert(
            "trash_action_error_title",
            isPresented: actionErrorBinding,
            presenting: actionError
        ) { _ in
            Button("button_ok", role: .cancel) { actionError = nil }
        } message: { message in
            Text(message)
        }
        .confirmationDialog(
            Text("trash_purge_confirm_title"),
            isPresented: pendingPurgeBinding,
            presenting: pendingPurge
        ) { pending in
            Button("trash_action_purge", role: .destructive) {
                Task { await performPurge(pending) }
            }
            Button("button_cancel", role: .cancel) {
                pendingPurge = nil
            }
        } message: { _ in
            Text("trash_purge_confirm_message")
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && sessions.isEmpty && visiblePhotos.isEmpty {
            ProgressView("trash_loading")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appBackgroundShield()
        } else if let loadError, sessions.isEmpty && visiblePhotos.isEmpty {
            ContentUnavailableView {
                Text("trash_load_error_title")
            } description: {
                Text(loadError)
            } actions: {
                Button("button_retry") {
                    Task { await refresh() }
                }
            }
            .appBackgroundShield()
        } else if sessions.isEmpty && visiblePhotos.isEmpty {
            ContentUnavailableView(
                "trash_empty_title",
                systemImage: "trash",
                description: Text("trash_empty_description")
            )
            .appBackgroundShield()
        } else {
            List {
                if !sessions.isEmpty {
                    Section("trash_section_sessions") {
                        ForEach(sessions, id: \.id) { session in
                            sessionRow(session)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        Task { await restoreSession(session) }
                                    } label: {
                                        Label("trash_action_restore", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                }

                if !visiblePhotos.isEmpty {
                    Section("trash_section_photos") {
                        ForEach(visiblePhotos, id: \.id) { photo in
                            photoRow(photo)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        Task { await restorePhoto(photo) }
                                    } label: {
                                        Label("trash_action_restore", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(.blue)

                                    Button(role: .destructive) {
                                        pendingPurge = .photo(photo)
                                    } label: {
                                        Label("trash_action_purge", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await refresh() }
            .appBackgroundShield()
        }
    }

    /// Photos cascaded by a session delete are represented by the session row.
    /// Showing them again as independent photo rows would let users restore a
    /// photo while its parent session remains trashed, stranding the photo.
    private var visiblePhotos: [Photo] {
        let deletedSessionIds = Set(sessions.map(\.id))
        return photos.filter { !deletedSessionIds.contains($0.sessionId) }
    }

    private func sessionRow(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(session.name)
                .font(.headline)
                .lineLimit(2)
            if let deletedAt = session.deletedAt {
                Text(deletedAt.formatted(date: .numeric, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func photoRow(_ photo: Photo) -> some View {
        HStack(spacing: Spacing.md) {
            ThumbnailView(photo: photo)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(photo.capturedAt.formatted(date: .numeric, time: .shortened))
                    .font(.subheadline)
                if let deletedAt = photo.deletedAt {
                    Text(deletedAt.formatted(date: .numeric, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Actions

    @MainActor
    private func refresh() async {
        isLoading = true
        loadError = nil
        do {
            async let sessionsTask = deps.mediaStorage.fetchDeletedSessions()
            async let photosTask = deps.mediaStorage.fetchDeletedPhotos()
            sessions = try await sessionsTask
            photos = try await photosTask
        } catch {
            loadError = String(describing: error)
        }
        isLoading = false
    }

    @MainActor
    private func restorePhoto(_ photo: Photo) async {
        do {
            try await deps.mediaStorage.restorePhoto(id: photo.id)
            await refresh()
        } catch {
            actionError = String(describing: error)
        }
    }

    @MainActor
    private func restoreSession(_ session: Session) async {
        do {
            try await deps.mediaStorage.restoreSession(sessionId: session.id)
            await refresh()
        } catch {
            actionError = String(describing: error)
        }
    }

    @MainActor
    private func performPurge(_ pending: PendingPurge) async {
        defer { pendingPurge = nil }
        do {
            switch pending {
            case .photo(let photo):
                try await deps.mediaStorage.purgePhoto(id: photo.id)
            }
            await refresh()
        } catch {
            actionError = String(describing: error)
        }
    }

    private var actionErrorBinding: Binding<Bool> {
        Binding(
            get: { actionError != nil },
            set: { newValue in
                if !newValue { actionError = nil }
            }
        )
    }

    private var pendingPurgeBinding: Binding<Bool> {
        Binding(
            get: { pendingPurge != nil },
            set: { newValue in
                if !newValue { pendingPurge = nil }
            }
        )
    }
}

/// E1.c는 photo 단위 purge만 지원. session purge UI는 storage API(`purgeSession`)가
/// 함께 들어오는 E1.d 또는 E5에서 enum case 확장.
private enum PendingPurge: Identifiable {
    case photo(Photo)

    var id: String {
        switch self {
        case .photo(let p): return "photo-\(p.id)"
        }
    }
}
