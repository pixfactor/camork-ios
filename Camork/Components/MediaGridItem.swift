import SwiftUI
import UIKit

struct MediaGridItem: View {
    let item: MediaItem
    var isSelectMode: Bool = false
    var isSelected: Bool = false

    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            thumbnailContent
                .aspectRatio(1, contentMode: .fit)
                .clipped()
                .cornerRadius(4)

            if item.mediaType == .video {
                videoOverlay
            }

            if isSelectMode {
                selectionOverlay
            }
        }
        .task(id: item.thumbnailFileName) {
            thumbnail = await ThumbnailCache.shared.thumbnail(for: item.thumbnailFileName)
        }
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(Color(.systemGray5))
                .overlay(
                    Image(systemName: item.mediaType == .video ? "video.fill" : "photo.fill")
                        .foregroundStyle(Color(.systemGray3))
                        .font(.title2)
                )
        }
    }

    private var videoOverlay: some View {
        HStack(spacing: 3) {
            Image(systemName: "play.fill")
                .font(.system(size: 9, weight: .semibold))
            if let duration = item.duration {
                Text(formattedDuration(duration))
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(.black.opacity(0.55))
        .cornerRadius(4)
        .padding(5)
    }

    private var selectionOverlay: some View {
        ZStack(alignment: .topTrailing) {
            if isSelected {
                Color.black.opacity(0.25)
            }
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(isSelected ? Color.accentColor : .white)
                .shadow(color: .black.opacity(0.4), radius: 2)
                .padding(5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
