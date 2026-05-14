import Foundation
import SwiftData

@Model
final class Folder {
    var id: UUID
    var name: String
    var colorHex: String
    var createdAt: Date
    var sortOrder: Int
    @Relationship(deleteRule: .cascade, inverse: \MediaItem.folder)
    var items: [MediaItem]

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#007AFF",
        createdAt: Date = .now,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.items = []
    }

    var itemCount: Int {
        items.count
    }

    var latestThumbnail: String? {
        items.sorted { $0.capturedAt > $1.capturedAt }.first?.thumbnailFileName
    }
}
