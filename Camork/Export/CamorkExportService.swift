import Foundation

struct CamorkExportRows: Sendable {
    let sessions: [Session]
    let photos: [Photo]
}

struct CamorkExportManifest: Codable, Sendable {
    let schemaVersion: Int
    let exportedAt: Date
    let sessions: [SessionRecord]
    let photos: [PhotoRecord]

    struct SessionRecord: Codable, Sendable {
        let id: UUID
        let name: String
        let note: String?
        let createdAt: Date
        let endedAt: Date?
        let firstLocation: LocationSnapshot?
        let deletedAt: Date?
    }

    struct PhotoRecord: Codable, Sendable {
        let id: UUID
        let sessionId: UUID
        let fileName: String
        let kind: MediaKind
        let capturedAt: Date
        let location: LocationSnapshot?
        let exif: ExifData?
        let note: String?
        let deletedAt: Date?
        let archivePath: String
    }
}

actor CamorkExportService {
    private let mediaStorage: MediaStorage
    private let temporaryRoot: URL
    private let now: @Sendable () -> Date

    init(
        mediaStorage: MediaStorage,
        temporaryRoot: URL = FileManager.default.temporaryDirectory,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.mediaStorage = mediaStorage
        self.temporaryRoot = temporaryRoot
        self.now = now
    }

    func prepareExport() async throws -> URL {
        let rows = try await mediaStorage.fetchExportRows()
        let exportDate = now()
        let root = temporaryRoot
            .appendingPathComponent("Camork", isDirectory: true)
            .appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let outputURL = root.appendingPathComponent(fileName(for: exportDate))
        var entries: [ZipArchiveEntry] = []
        let manifest = CamorkExportManifest(
            schemaVersion: 1,
            exportedAt: exportDate,
            sessions: rows.sessions.map {
                CamorkExportManifest.SessionRecord(
                    id: $0.id,
                    name: $0.name,
                    note: $0.note,
                    createdAt: $0.createdAt,
                    endedAt: $0.endedAt,
                    firstLocation: $0.firstLocation,
                    deletedAt: $0.deletedAt
                )
            },
            photos: rows.photos.map {
                CamorkExportManifest.PhotoRecord(
                    id: $0.id,
                    sessionId: $0.sessionId,
                    fileName: $0.fileName,
                    kind: $0.kind,
                    capturedAt: $0.capturedAt,
                    location: $0.location,
                    exif: $0.exif,
                    note: $0.note,
                    deletedAt: $0.deletedAt,
                    archivePath: "Media/\($0.fileName)"
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        entries.append(ZipArchiveEntry(path: "metadata.json", data: try encoder.encode(manifest)))

        for photo in rows.photos {
            let data = try await mediaStorage.loadPhotoData(for: photo)
            entries.append(ZipArchiveEntry(path: "Media/\(photo.fileName)", data: data))
        }

        try ZipArchiveWriter.write(entries: entries, to: outputURL)
        return outputURL
    }

    func cleanupExport(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func fileName(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
        return "Camork-\(stamp).zip"
    }
}
