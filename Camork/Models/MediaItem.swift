import Foundation
import SwiftData

@Model
final class MediaItem {
    var id: UUID
    var mediaTypeRaw: String
    var fileName: String
    var thumbnailFileName: String
    var memo: String
    var templateTag: String?
    var isDeleted: Bool = false
    var deletedAt: Date? = nil
    var capturedAt: Date
    var latitude: Double?
    var longitude: Double?
    var duration: Double?
    var folder: Folder?

    init(
        id: UUID = UUID(),
        mediaType: MediaType,
        fileName: String,
        thumbnailFileName: String,
        memo: String = "",
        templateTag: String? = nil,
        isDeleted: Bool = false,
        deletedAt: Date? = nil,
        capturedAt: Date = .now,
        latitude: Double? = nil,
        longitude: Double? = nil,
        duration: Double? = nil,
        folder: Folder? = nil
    ) {
        self.id = id
        self.mediaTypeRaw = mediaType.rawValue
        self.fileName = fileName
        self.thumbnailFileName = thumbnailFileName
        self.memo = memo
        self.templateTag = templateTag
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
        self.capturedAt = capturedAt
        self.latitude = latitude
        self.longitude = longitude
        self.duration = duration
        self.folder = folder
    }

    var mediaType: MediaType {
        get { MediaType(rawValue: mediaTypeRaw) ?? .photo }
        set { mediaTypeRaw = newValue.rawValue }
    }

    var fileURL: URL {
        FileStorageManager.shared.getMediaURL(fileName: fileName)
    }

    var thumbnailURL: URL {
        FileStorageManager.shared.getThumbnailURL(fileName: thumbnailFileName)
    }
}
