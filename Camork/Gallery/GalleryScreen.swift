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

    var body: some View {
        NavigationStack {
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
                NavigationLink {
                    SessionDetailScreen(session: item.session)
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
