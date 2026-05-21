import SwiftUI

/// Gallery root screen.
///
/// Owns data loading and screen states. Session card composition lives in
/// `SessionCardView` so thumbnail loading can land as a focused follow-up.
struct GalleryScreen: View {
    @EnvironmentObject private var deps: DependencyContainer

    @State private var sessions: [SessionWithPreview] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showTrash = false
    @State private var navigationPath: [UUID] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            content
                .navigationTitle("gallery_title")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showTrash = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel(Text("gallery_trash_a11y"))
                    }
                }
                .navigationDestination(for: UUID.self) { sessionId in
                    sessionDetailDestination(sessionId: sessionId)
                }
        }
        .task {
            await refresh()
        }
        .sheet(isPresented: $showTrash, onDismiss: {
            Task { await refresh() }
        }) {
            TrashScreen()
                .environmentObject(deps)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && sessions.isEmpty {
            ProgressView("gallery_loading")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appBackgroundShield()
        } else if let loadError, sessions.isEmpty {
            ContentUnavailableView {
                Text("gallery_load_error_title")
            } description: {
                Text(loadError)
            } actions: {
                Button("button_retry") {
                    Task { await refresh() }
                }
            }
            .appBackgroundShield()
        } else if sessions.isEmpty {
            ContentUnavailableView(
                "gallery_empty_title",
                systemImage: "square.grid.2x2",
                description: Text("gallery_empty_description")
            )
            .appBackgroundShield()
        } else {
            List(sessions, id: \.session.id) { item in
                Button {
                    navigationPath.append(item.session.id)
                } label: {
                    SessionCardView(item: item)
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(
                    top: Spacing.sm,
                    leading: Spacing.md,
                    bottom: Spacing.sm,
                    trailing: Spacing.md
                ))
            }
            .listStyle(.plain)
            .refreshable {
                await refresh()
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: Spacing.md)
            }
            .appBackgroundShield()
        }
    }

    @ViewBuilder
    private func sessionDetailDestination(sessionId: UUID) -> some View {
        if let session = sessions.first(where: { $0.session.id == sessionId })?.session {
            SessionDetailScreen(session: session) { savedName, savedNote in
                applyInfoChange(sessionId: session.id, name: savedName, note: savedNote)
            }
        } else {
            ContentUnavailableView("gallery_load_error_title", systemImage: "exclamationmark.triangle")
        }
    }

    @MainActor
    private func refresh() async {
        isLoading = true
        loadError = nil
        do {
            sessions = try await deps.mediaStorage.fetchSessionsWithPreview()
        } catch {
            loadError = String(describing: error)
        }
        isLoading = false
    }

    /// SessionDetailScreen 저장 콜백 — 화면에 표시 중인 `sessions` 배열의 해당 row만
    /// 새 name/note로 교체한다. 전체 fetch 없이 즉시 카드가 갱신되며, nav pop 전후의
    /// stale 상태를 차단한다.
    @MainActor
    private func applyInfoChange(sessionId: UUID, name: String, note: String?) {
        guard let index = sessions.firstIndex(where: { $0.session.id == sessionId }) else { return }
        let old = sessions[index].session
        let updated = Session(
            id: old.id,
            name: name,
            note: note,
            createdAt: old.createdAt,
            endedAt: old.endedAt,
            firstLocation: old.firstLocation,
            deletedAt: old.deletedAt
        )
        sessions[index] = SessionWithPreview(session: updated, preview: sessions[index].preview)
    }
}

#if DEBUG
#Preview("Gallery — Dark") {
    GalleryScreen()
        .environmentObject(DependencyContainer.previewStub())
        .preferredColorScheme(.dark)
}

#Preview("Gallery — Light") {
    GalleryScreen()
        .environmentObject(DependencyContainer.previewStub())
        .preferredColorScheme(.light)
}
#endif
