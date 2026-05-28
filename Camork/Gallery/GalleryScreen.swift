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
    @State private var viewMode: GalleryViewMode = .list
    @State private var dateFilter: SessionDateFilter = .all
    @State private var showCustomDateFilter = false
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var navigationPath: [UUID] = []

    private var filteredSessions: [SessionWithPreview] {
        sessions.filter { dateFilter.contains($0.session.createdAt) }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            content
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showTrash = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel(Text("gallery_trash_a11y"))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        dateFilterMenu
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
        .sheet(isPresented: $showCustomDateFilter) {
            customDateFilterSheet
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
        } else if filteredSessions.isEmpty {
            VStack(spacing: 16) {
                galleryHeader
                ContentUnavailableView(
                    "gallery_filter_empty_title",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("gallery_filter_empty_description")
                )
            }
            .appBackgroundShield()
        } else {
            Group {
                switch viewMode {
                case .list:
                    galleryList
                case .map:
                    VStack(spacing: 0) {
                        galleryHeader
                        GalleryMapView(sessions: filteredSessions) { sessionId in
                            navigationPath.append(sessionId)
                        }
                        .ignoresSafeArea(edges: .bottom)
                    }
                }
            }
            .appBackgroundShield()
        }
    }

    private var galleryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("gallery_title")
                .font(.largeTitle.weight(.bold))
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("gallery_view_mode_picker", selection: $viewMode) {
                Label("gallery_view_mode_list", systemImage: "square.grid.2x2")
                    .tag(GalleryViewMode.list)
                Label("gallery_view_mode_map", systemImage: "map")
                    .tag(GalleryViewMode.map)
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
    }

    private var dateFilterMenu: some View {
        Menu {
            Button {
                dateFilter = .all
            } label: {
                Label("gallery_filter_all", systemImage: "tray.full")
            }
            Button {
                dateFilter = .today
            } label: {
                Label("gallery_filter_today", systemImage: "calendar")
            }
            Button {
                dateFilter = .thisWeek
            } label: {
                Label("gallery_filter_this_week", systemImage: "calendar.badge.clock")
            }
            Button {
                dateFilter = .thisMonth
            } label: {
                Label("gallery_filter_this_month", systemImage: "calendar.circle")
            }
            Button {
                openCustomDateFilter()
            } label: {
                Label("gallery_filter_custom", systemImage: "calendar.badge.plus")
            }
        } label: {
            Image(systemName: "calendar")
        }
        .accessibilityLabel(Text("gallery_filter_a11y"))
    }

    private var customDateFilterSheet: some View {
        GalleryCalendarFilterSheet(
            sessions: sessions,
            startDate: $customStartDate,
            endDate: $customEndDate
        ) {
            dateFilter = .custom(start: customStartDate, end: customEndDate)
            showCustomDateFilter = false
        }
    }

    private func openCustomDateFilter() {
        if case .custom(let start, let end) = dateFilter {
            customStartDate = start
            customEndDate = end
        } else {
            let anchor = sessions.first?.session.createdAt ?? Date()
            customStartDate = anchor
            customEndDate = anchor
        }
        showCustomDateFilter = true
    }

    private var galleryList: some View {
        ZStack(alignment: .top) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear
                        .frame(height: GalleryChromeLayout.headerReserve)

                    ForEach(filteredSessions, id: \.session.id) { item in
                        Button {
                            navigationPath.append(item.session.id)
                        } label: {
                            SessionCardView(item: item)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, Spacing.sm)
                        .padding(.horizontal, Spacing.md)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await refresh()
            }
            .ignoresSafeArea(edges: .bottom)
            .camorkScrollEdgeEffects(
                topEdgeHeight: GalleryChromeLayout.topEdgeEffectHeight,
                bottomEdgeHeight: GalleryChromeLayout.bottomEdgeEffectHeight
            )

            galleryHeader
                .background(alignment: .top) {
                    GalleryHeaderMaterial()
                }
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

private enum GalleryViewMode: Hashable {
    case list
    case map
}

private enum GalleryChromeLayout {
    static let headerReserve: CGFloat = 122
    static let topEdgeEffectHeight: CGFloat = 132
    static let bottomEdgeEffectHeight: CGFloat = 124
}

private struct GalleryHeaderMaterial: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.72),
                        .init(color: .black.opacity(0), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .padding(.bottom, -Spacing.lg)
            .allowsHitTesting(false)
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
