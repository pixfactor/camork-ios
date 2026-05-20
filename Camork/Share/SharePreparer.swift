import Foundation

struct ShareBundle: Sendable {
    let fileURLs: [URL]
    let autoText: String
    let tempDir: URL
}

actor SharePreparer {
    private let mediaStorage: MediaStorage
    private let temporaryRoot: URL
    private let now: @Sendable () -> Date
    private let expirationInterval: TimeInterval

    init(
        mediaStorage: MediaStorage,
        temporaryRoot: URL = FileManager.default.temporaryDirectory,
        now: @escaping @Sendable () -> Date = { Date() },
        expirationInterval: TimeInterval = 24 * 60 * 60
    ) {
        self.mediaStorage = mediaStorage
        self.temporaryRoot = temporaryRoot
        self.now = now
        self.expirationInterval = expirationInterval
    }

    func prepare(
        photos: [Photo],
        session: Session,
        includeLocation: Bool,
        includeTime: Bool
    ) async throws -> ShareBundle {
        let tempDir = shareRoot()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: tempDir,
                withIntermediateDirectories: true
            )

            var fileURLs: [URL] = []
            for (index, photo) in photos.enumerated() {
                let original = try await mediaStorage.loadPhotoData(for: photo)
                let sanitized = try ShareSanitizer.sanitize(
                    data: original,
                    stripLocation: !includeLocation
                )
                let url = tempDir.appendingPathComponent("photo-\(index).heic")
                try sanitized.write(
                    to: url,
                    options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                )
                fileURLs.append(url)
            }

            return ShareBundle(
                fileURLs: fileURLs,
                autoText: autoText(
                    session: session,
                    photos: photos,
                    includeLocation: includeLocation,
                    includeTime: includeTime
                ),
                tempDir: tempDir
            )
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            throw error
        }
    }

    func cleanup(_ bundle: ShareBundle) {
        try? FileManager.default.removeItem(at: bundle.tempDir)
    }

    func cleanupExpired() {
        let root = shareRoot()
        guard FileManager.default.fileExists(atPath: root.path) else { return }

        let cutoff = now().addingTimeInterval(-expirationInterval)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for url in urls where isExpired(url, cutoff: cutoff) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func shareRoot() -> URL {
        temporaryRoot
            .appendingPathComponent("Camork", isDirectory: true)
            .appendingPathComponent("Share", isDirectory: true)
    }

    private func autoText(
        session: Session,
        photos: [Photo],
        includeLocation: Bool,
        includeTime: Bool
    ) -> String {
        var parts = ["[\(session.name)]"]

        if includeTime {
            parts.append(Self.formatShareDate(session.createdAt))
        }

        if includeLocation, let placeName = firstPlaceName(session: session, photos: photos) {
            parts.append(placeName)
        }

        return "\(parts.joined(separator: " · ")) — 사진 \(photos.count)장"
    }

    private func firstPlaceName(session: Session, photos: [Photo]) -> String? {
        let candidates = [session.firstLocation?.placeName] + photos.map { $0.location?.placeName }
        return candidates.compactMap { name in
            let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }.first
    }

    private static func formatShareDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func isExpired(_ url: URL, cutoff: Date) -> Bool {
        guard let values = try? url.resourceValues(
            forKeys: [.contentModificationDateKey, .creationDateKey]
        ) else {
            return false
        }
        let date = values.contentModificationDate ?? values.creationDate
        return date.map { $0 < cutoff } ?? false
    }
}
