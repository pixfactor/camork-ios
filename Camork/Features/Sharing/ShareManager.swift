import SwiftUI
import UIKit

enum ShareManager {
    /// Converts MediaItems to shareable file URLs
    static func shareItems(_ items: [MediaItem]) -> [Any] {
        items
            .sorted { $0.capturedAt < $1.capturedAt }
            .map { FileStorageManager.shared.getMediaURL(fileName: $0.fileName) as Any }
    }

    static func shareItem(_ item: MediaItem) -> [Any] {
        shareItems([item])
    }

    /// Creates a UIActivityViewController for the given items
    static func shareSheet(items: [Any]) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        controller.excludedActivityTypes = [
            .assignToContact,
            .addToReadingList,
            .openInIBooks
        ]
        return controller
    }
}

/// SwiftUI wrapper that handles async item loading before presenting share sheet
struct ShareButton: View {
    let items: [MediaItem]
    @State private var isLoading = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false

    var body: some View {
        Button {
            prepareAndShare()
        } label: {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .disabled(isLoading)
        .sheet(isPresented: $showShareSheet) {
            ShareSheetView(activityItems: shareItems)
        }
    }

    private func prepareAndShare() {
        shareItems = ShareManager.shareItems(items)
        if !shareItems.isEmpty {
            showShareSheet = true
        }
    }
}
