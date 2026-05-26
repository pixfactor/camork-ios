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
    /// 저장 성공 시 호출. 호출자(GalleryScreen)가 자기 `sessions` 배열의 해당 row를
    /// 즉시 새 값으로 교체해 카드가 stale하지 않게 한다 (nav pop 전 카드 갱신).
    let onSessionInfoChanged: ((_ name: String, _ note: String?) -> Void)?

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
    @State private var showFullNote: Bool = false

    /// 세션 헤더에서 메모를 기본 노출할 줄 수. 초과분은 "더보기" sheet로 분리해
    /// 사진 그리드가 메모 길이에 따라 아래로 밀리지 않게 한다.
    private static let sessionNoteCollapsedLineLimit = 8

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.xs),
        GridItem(.flexible(), spacing: Spacing.xs),
        GridItem(.flexible(), spacing: Spacing.xs)
    ]

    init(
        session: Session,
        onSessionInfoChanged: ((_ name: String, _ note: String?) -> Void)? = nil
    ) {
        self.session = session
        self.onSessionInfoChanged = onSessionInfoChanged
        self._sessionName = State(initialValue: session.name)
        self._sessionNote = State(initialValue: session.note)
    }

    /// 사용자가 sheet에서 편집한 직후의 name/note 값을 반영한 Session 사본. ShareEntryButton과
    /// PhotoDetailView 같이 자식에 흐르는 share/메타 텍스트가 즉시 새 값을 사용하도록 한다 —
    /// 원본 `session` (init parameter) 는 immutable이라 직접 갱신 불가.
    private var liveSession: Session {
        Session(
            id: session.id,
            name: sessionName,
            note: sessionNote,
            createdAt: session.createdAt,
            endedAt: session.endedAt,
            firstLocation: session.firstLocation,
            deletedAt: session.deletedAt
        )
    }

    var body: some View {
        content
            .navigationTitle(sessionName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        sheet = .info
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel(Text("session_detail_edit_info_a11y"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: Spacing.md) {
                        ShareEntryButton(
                            session: liveSession,
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
                    .padding(.horizontal, Spacing.sm)
                }
            }
            .task {
                await refresh()
            }
            .fullScreenCover(item: $detailItem) { item in
                PhotoDetailView(
                    photos: photos,
                    initialPhotoId: item.photo.id,
                    initialData: item.data,
                    dataLoader: { try await deps.mediaStorage.loadPhotoData(for: $0) },
                    memoEditor: PhotoMemoEditor(mediaStorage: deps.mediaStorage),
                    onDismiss: { detailItem = nil },
                    session: liveSession,
                    sharePreparer: deps.sharePreparer
                )
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .info:
                    SessionInfoEditSheet(
                        sessionId: session.id,
                        initialName: sessionName,
                        initialNote: sessionNote,
                        editor: SessionInfoEditor(mediaStorage: deps.mediaStorage)
                    ) { savedName, savedNote in
                        sessionName = savedName
                        sessionNote = savedNote
                        onSessionInfoChanged?(savedName, savedNote)
                    }
                }
            }
            .sheet(isPresented: $showFullNote) {
                if let note = sessionNote, !note.isEmpty {
                    SessionNoteReadSheet(note: note)
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
                    Color.clear
                        .frame(height: ChromeFadeMask.scrollReserve)
                }
                .padding(Spacing.md)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.bottom, 0, for: .scrollContent)
            .refreshable {
                await refresh()
            }
            .ignoresSafeArea(edges: .bottom)
            .camorkScrollEdgeEffects()
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
                sessionNoteSummary(sessionNote)
                    .padding(.top, Spacing.xs)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    /// 세션 메모는 기본 8줄까지만 노출. 8줄을 초과하면 truncate + "더보기" 버튼을
    /// 보여주고, 누르면 read-only sheet에서 전체 메모를 표시한다 — 사진 그리드가
    /// 메모 길이에 따라 끝없이 아래로 밀리지 않게 하는 핵심 안전망.
    @ViewBuilder
    private func sessionNoteSummary(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(note)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(Self.sessionNoteCollapsedLineLimit)
                .multilineTextAlignment(.leading)

            if Self.exceedsCollapsedLineLimit(note) {
                Button("session_detail_note_more") {
                    showFullNote = true
                }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 줄바꿈 개수로 8줄 초과 여부를 가늠. UIKit `TextLayoutManager`를 거치지 않고도
    /// "사용자가 직접 줄바꿈을 8회 이상 넣었다" 시그널을 잡아낸다. wrap된 긴 한 줄은
    /// 본 함수 기준 1줄이지만 SwiftUI `lineLimit(8)`이 시각적 truncation을 처리.
    /// 두 검사를 함께 두면 "사용자 줄바꿈 많은 메모" + "한 줄로 매우 긴 메모" 모두
    /// 더보기 버튼이 노출된다.
    private static func exceedsCollapsedLineLimit(_ note: String) -> Bool {
        let newlineCount = note.reduce(into: 0) { count, character in
            if character.isNewline { count += 1 }
        }
        if newlineCount >= sessionNoteCollapsedLineLimit { return true }

        // 폭이 좁은 화면에서 한 줄이 줄바꿈 없이 매우 길면 wrap 추정치로 추가 보호.
        // 보수적으로 한국어/영문 혼합 평균 가독 행폭(40 char) 기준 8행 분량.
        let approximateCharsPerLine = 40
        return note.count > sessionNoteCollapsedLineLimit * approximateCharsPerLine
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
    /// 이름/메모 통합 편집 시트.
    case info

    var id: String {
        switch self {
        case .info: "info"
        }
    }
}

private struct SessionPhotoDetailItem: Identifiable {
    let photo: Photo
    let data: Data
    var id: UUID { photo.id }
}

/// Read-only sheet for the full session note. Mirrors `SessionInfoEditSheet`의
/// NavigationStack chrome 패턴이라 사용자에게 시각적으로 연속되어 보이며,
/// 헤더의 lineLimit(8) cap에 의해 잘린 부분까지 자유롭게 스크롤로 읽을 수 있다.
private struct SessionNoteReadSheet: View {
    @Environment(\.dismiss) private var dismiss
    let note: String

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(note)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(Spacing.md)
            }
            .navigationTitle(Text("session_detail_note_read_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("button_close") { dismiss() }
                }
            }
        }
    }
}

#if DEBUG
private struct SessionDetailScreenPreview: View {
    @EnvironmentObject private var deps: DependencyContainer
    @State private var session: Session?

    var body: some View {
        NavigationStack {
            if let session {
                SessionDetailScreen(session: session)
            } else {
                ProgressView("session_detail_loading")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .appBackgroundShield()
                    .task {
                        await loadPreviewSession()
                    }
            }
        }
    }

    @MainActor
    private func loadPreviewSession() async {
        guard session == nil else { return }
        do {
            session = try await deps.mediaStorage.fetchSessionsWithPreview().first?.session
        } catch {
            session = nil
        }
    }
}

#Preview("Session Detail — Dark") {
    SessionDetailScreenPreview()
        .environmentObject(DependencyContainer.previewStub())
        .preferredColorScheme(.dark)
}

#Preview("Session Detail — Light") {
    SessionDetailScreenPreview()
        .environmentObject(DependencyContainer.previewStub())
        .preferredColorScheme(.light)
}
#endif
