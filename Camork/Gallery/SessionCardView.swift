import Foundation
import SwiftUI

/// Gallery session card (Plan C Phase 3.2).
///
/// Thumbnail slots delegate loading to `ThumbnailView`; this card owns only layout,
/// metadata, and action affordances.
struct SessionCardView: View {
    let item: SessionWithPreview

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.xs),
        GridItem(.flexible(), spacing: Spacing.xs)
    ]

    var body: some View {
        CamorkCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                previewGrid
                HStack(alignment: .top, spacing: Spacing.md) {
                    metadata
                    Spacer(minLength: Spacing.sm)
                    actionButtons
                }
            }
        }
    }

    private var previewGrid: some View {
        LazyVGrid(columns: columns, spacing: Spacing.xs) {
            ForEach(0..<4, id: \.self) { index in
                ZStack {
                    SessionPreviewTile(photo: photo(at: index))
                    if index == 3, hiddenPhotoCount > 0 {
                        hiddenCountBadge
                    }
                }
                .aspectRatio(1, contentMode: .fit)
            }
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(item.session.name)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: Spacing.sm) {
                Text(item.session.createdAt.formatted(date: .numeric, time: .shortened))
                if let placeName = item.session.firstLocation?.placeName, !placeName.isEmpty {
                    Text(placeName)
                        .lineLimit(1)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Label(photoCountText, systemImage: "photo")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: Spacing.xs) {
            Button {} label: {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)
            .disabled(true)
            .accessibilityLabel(Text("button_share"))

            Button {} label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)
            .disabled(true)
            .accessibilityLabel(Text("session_card_more_a11y"))
        }
    }

    private var hiddenCountBadge: some View {
        Text("+\(hiddenPhotoCount)")
            .font(.headline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var hiddenPhotoCount: Int {
        max(item.preview.totalPhotoCount - item.preview.previewPhotos.count, 0)
    }

    private var photoCountText: String {
        let count = item.preview.totalPhotoCount
        if count == 1 {
            return String(localized: "session_card_photo_count_one")
        }
        return String(
            format: String(localized: "session_card_photo_count_other_format"),
            count
        )
    }

    private func photo(at index: Int) -> Photo? {
        guard item.preview.previewPhotos.indices.contains(index) else { return nil }
        return item.preview.previewPhotos[index]
    }
}

private struct SessionPreviewTile: View {
    let photo: Photo?

    var body: some View {
        ZStack {
            if let photo {
                ThumbnailView(photo: photo)
            } else {
                RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                    .fill(Color.camorkFill.opacity(0.4))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
    }
}
