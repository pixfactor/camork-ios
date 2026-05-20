import Foundation
import SwiftUI
import UIKit

/// Async thumbnail image surface (Plan C Phase 3.3).
///
/// Loading is intentionally view-local: MediaStorage owns cache/read/generate behavior,
/// while this view owns only lifecycle cancellation and placeholder fallback.
struct ThumbnailView: View {
    @EnvironmentObject private var deps: DependencyContainer

    let photo: Photo

    @State private var data: Data?
    @State private var loadTask: Task<Void, Never>?
    @State private var loadGeneration = 0

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear {
            startLoadIfNeeded()
        }
        .onDisappear {
            cancelLoad()
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
            .fill(Color.camorkFill.opacity(0.4))
    }

    @MainActor
    private func startLoadIfNeeded() {
        guard data == nil, loadTask == nil else { return }
        loadGeneration += 1
        let generation = loadGeneration
        loadTask = Task {
            await load(generation: generation)
        }
    }

    @MainActor
    private func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
        loadGeneration += 1
    }

    @MainActor
    private func load(generation: Int) async {
        let loadedData = try? await deps.mediaStorage.loadThumbnailData(for: photo)
        guard !Task.isCancelled, generation == loadGeneration else { return }
        data = loadedData
        loadTask = nil
    }
}
