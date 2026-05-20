import SwiftUI

/// Gallery root screen (Plan C Phase 3.1).
///
/// Phase 3.1 owns only data loading, empty/loading/error states, and a minimal session
/// summary row. Rich 4-photo cards are introduced by `SessionCardView` in Phase 3.2.
struct GalleryScreen: View {
    @EnvironmentObject private var deps: DependencyContainer

    @State private var sessions: [SessionWithPreview] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("gallery_title")
                .toolbar {
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
                GallerySessionSummaryRow(item: item)
            }
            .listStyle(.plain)
            .refreshable {
                await refresh()
            }
            .appBackgroundShield()
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
}

private struct GallerySessionSummaryRow: View {
    let item: SessionWithPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.session.name)
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 10) {
                Text(item.session.createdAt.formatted(date: .numeric, time: .shortened))
                if let placeName = item.session.firstLocation?.placeName, !placeName.isEmpty {
                    Text(placeName)
                        .lineLimit(1)
                }
                Label("\(item.preview.totalPhotoCount)", systemImage: "photo")
                    .labelStyle(.titleAndIcon)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}
