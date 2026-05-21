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
    private let metadataIconTextSpacing = Spacing.xs

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

            metadataRow(systemImage: "photo", text: photoCountText)

            if let noteFirstLine = Self.firstNonEmptyLine(item.session.note) {
                metadataRow(systemImage: "text.bubble", text: noteFirstLine)
                    .lineLimit(1)
            }
        }
    }

    private func metadataRow(systemImage: String, text: String) -> some View {
        HStack(spacing: metadataIconTextSpacing) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
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

#if DEBUG
private func previewSessionCardSample(
    name: String,
    note: String?,
    placeName: String?,
    photoCount: Int,
    previewCount: Int
) -> SessionWithPreview {
    let location = placeName.map {
        LocationSnapshot(latitude: 37.5, longitude: 127.0, horizontalAccuracy: 10, placeName: $0)
    }
    let session = Session(
        id: UUID(),
        name: name,
        note: note,
        createdAt: Date(),
        firstLocation: location
    )
    let photos = (0..<previewCount).map { i in
        Photo(
            id: UUID(),
            sessionId: session.id,
            fileName: "\(UUID().uuidString).heic",
            kind: .photo,
            capturedAt: Date().addingTimeInterval(TimeInterval(-i * 60))
        )
    }
    return SessionWithPreview(
        session: session,
        preview: SessionPreview(
            sessionId: session.id,
            totalPhotoCount: photoCount,
            previewPhotos: photos
        )
    )
}

#Preview("Cards — Dark") {
    ScrollView {
        VStack(spacing: Spacing.md) {
            SessionCardView(item: previewSessionCardSample(
                name: "성수동 사무실 외관 점검",
                note: "1층 외벽 균열 사진 위주",
                placeName: "성수동, 서울",
                photoCount: 12,
                previewCount: 4
            ))
            SessionCardView(item: previewSessionCardSample(
                name: "판교 현장 배전반",
                note: nil,
                placeName: "판교, 성남",
                photoCount: 3,
                previewCount: 3
            ))
            SessionCardView(item: previewSessionCardSample(
                name: "강남 카페 인테리어 변경",
                note: "벽지 색상 후보 비교\n2026-05-22 미팅 자료",
                placeName: nil,
                photoCount: 1,
                previewCount: 1
            ))
        }
        .padding(Spacing.md)
    }
    .background(Color.camorkBackground)
    .environmentObject(DependencyContainer.previewStub())
    .preferredColorScheme(.dark)
}

#Preview("Cards — Light") {
    ScrollView {
        VStack(spacing: Spacing.md) {
            SessionCardView(item: previewSessionCardSample(
                name: "성수동 사무실 외관 점검",
                note: "1층 외벽 균열 사진 위주",
                placeName: "성수동, 서울",
                photoCount: 12,
                previewCount: 4
            ))
            SessionCardView(item: previewSessionCardSample(
                name: "판교 현장 배전반",
                note: nil,
                placeName: "판교, 성남",
                photoCount: 3,
                previewCount: 3
            ))
        }
        .padding(Spacing.md)
    }
    .background(Color.camorkBackground)
    .environmentObject(DependencyContainer.previewStub())
    .preferredColorScheme(.light)
}
#endif
