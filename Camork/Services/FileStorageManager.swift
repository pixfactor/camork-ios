import Foundation

actor FileStorageManager {
    static let shared = FileStorageManager()

    private let baseDirectory: URL

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        baseDirectory = documents.appendingPathComponent("CamorkMedia", isDirectory: true)
        let thumbnailsDir = baseDirectory.appendingPathComponent("thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
    }

    private func ensureDirectoryExists() {
        let thumbnailsDir = baseDirectory.appendingPathComponent("thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
    }

    func saveMedia(data: Data, fileName: String) async throws -> URL {
        ensureDirectoryExists()
        let fileURL = baseDirectory.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    func saveVideo(from tempURL: URL, fileName: String) async throws -> URL {
        ensureDirectoryExists()
        let destinationURL = baseDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        return destinationURL
    }

    func deleteMedia(fileName: String) async throws {
        let fileURL = baseDirectory.appendingPathComponent(fileName)
        let thumbnailURL = baseDirectory.appendingPathComponent("thumbnails").appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        if FileManager.default.fileExists(atPath: thumbnailURL.path) {
            try FileManager.default.removeItem(at: thumbnailURL)
        }
    }

    nonisolated func getMediaURL(fileName: String) -> URL {
        baseDirectory.appendingPathComponent(fileName)
    }

    nonisolated func getThumbnailURL(fileName: String) -> URL {
        baseDirectory.appendingPathComponent("thumbnails").appendingPathComponent(fileName)
    }

    nonisolated func generateUniqueFileName(extension ext: String) -> String {
        "\(UUID().uuidString).\(ext)"
    }

    func calculateStorageUsed() async -> Int64 {
        Self.storageBytesSync(in: baseDirectory)
    }

    private static func storageBytesSync(in directory: URL) -> Int64 {
        var totalSize: Int64 = 0
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            totalSize += Int64(size)
        }
        return totalSize
    }
}
