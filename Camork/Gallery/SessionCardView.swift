import Foundation
import SwiftUI

/// Gallery session card (Plan C Phase 3.2).
///
/// Thumbnail slots delegate loading to `ThumbnailView`; this card owns only layout,
/// and metadata.
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
                metadata
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

            if let noteFirstLine = Self.firstNonEmptyLine(item.session.note) {
                Label(noteFirstLine, systemImage: "text.bubble")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// Session note의 첫 non-empty line만 추출. 다중 라인 메모 중 시각적으로 노출할
    /// "요약 한 줄"이 필요한 경우 (카드 미리보기) 사용. trim한 결과가 빈 줄이면 다음
    /// 줄로 넘어가서 첫 non-empty 라인을 찾는다.
    private static func firstNonEmptyLine(_ note: String?) -> String? {
        guard let note else { return nil }
        for line in note.split(whereSeparator: { $0.isNewline }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
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
