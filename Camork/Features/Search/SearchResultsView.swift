import SwiftUI
import UIKit

struct SearchResultsView: View {
    let items: [MediaItem]

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    private var groupedByDate: [(key: String, value: [MediaItem])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy년 MM월 dd일"

        let grouped = Dictionary(grouping: items) { item in
            formatter.string(from: item.capturedAt)
        }
        return grouped.sorted { a, b in
            let df = DateFormatter()
            df.dateFormat = "yyyy년 MM월 dd일"
            let dateA = df.date(from: a.key) ?? Date.distantPast
            let dateB = df.date(from: b.key) ?? Date.distantPast
            return dateA > dateB
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedByDate, id: \.key) { section in
                    Section {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(section.value) { item in
                                if let folder = item.folder {
                                    NavigationLink(destination: MediaDetailView(folder: folder, initialItemID: item.id)) {
                                        SearchResultCell(item: item)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } header: {
                        Text(section.key)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.regularMaterial)
                    }
                }
            }
        }
    }
}

struct SearchResultCell: View {
    let item: MediaItem
    @State private var thumbnail: UIImage? = nil

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .overlay {
                            Image(systemName: item.mediaType == .video ? "video" : "photo")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fill)
            .clipped()

            VStack(alignment: .leading, spacing: 2) {
                if let folderName = item.folder?.name {
                    Text(folderName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.6))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(4)

            if item.mediaType == .video {
                HStack {
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .task {
            thumbnail = await ThumbnailCache.shared.thumbnail(for: item.thumbnailFileName)
        }
    }
}
