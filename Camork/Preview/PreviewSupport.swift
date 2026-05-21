#if DEBUG
import Foundation
import GRDB

/// SwiftUI Canvas / `#Preview` 지원 인프라. production 빌드는 `#if DEBUG` gate로 제외된다.
///
/// `DependencyContainer.previewStub()`는 실제 디스크 / 카메라를 건드리지 않고 in-memory
/// GRDB DB + `MemoryFileOps` + stub `CameraSession`을 묶어 preview 전용 컨테이너를
/// 만든다. 샘플 세션/사진을 시드해 Gallery 같은 화면이 즉시 의미 있는 카드를 그릴 수
/// 있다. 실제 이미지 바이트는 없으므로 thumbnail 슬롯은 placeholder로 그려진다 —
/// 카드 *레이아웃* 조정 목적에 충분.
extension DependencyContainer {
    @MainActor
    static func previewStub() -> DependencyContainer {
        let db: DatabaseQueue
        do {
            db = try DatabaseQueue()
            try Migrations.makeMigrator().migrate(db)
            try seedPreviewSampleData(into: db)
        } catch {
            fatalError("DependencyContainer.previewStub() DB setup failed: \(error)")
        }

        let fs = MemoryFileOps()
        let mediaStorage = MediaStorage(db: db, fs: fs)
        let sharePreparer = SharePreparer(mediaStorage: mediaStorage)
        let cameraSession = CameraSession(
            previewStubConfiguration: CameraSessionBuilder.makeConfiguration()
        )

        return DependencyContainer(
            previewMediaStorage: mediaStorage,
            previewSharePreparer: sharePreparer,
            previewLocationService: LocationService(),
            previewPermissionsService: PermissionsService(),
            previewCameraSession: cameraSession,
            previewAppLockController: AppLockController(startLocked: false)
        )
    }
}

/// Gallery preview용 3개 세션 + 각 세션 2~5장. 실제 image bytes는 없음.
private func seedPreviewSampleData(into db: any DatabaseWriter) throws {
    try db.write { db in
        let now = Date()
        let day: TimeInterval = 24 * 60 * 60

        let sessions: [(name: String, note: String?, daysAgo: Double, placeName: String?, photoCount: Int)] = [
            ("성수동 사무실 외관 점검", "1층 외벽 균열 사진 위주", 0, "성수동, 서울", 5),
            ("판교 현장 배전반", nil, 1, "판교, 성남", 3),
            ("강남 카페 인테리어 변경", "벽지 색상 후보 비교\n2026-05-22 미팅 자료", 3, "강남, 서울", 2)
        ]

        for entry in sessions {
            let createdAt = now.addingTimeInterval(-entry.daysAgo * day)
            let location = entry.placeName.map {
                LocationSnapshot(
                    latitude: 37.5,
                    longitude: 127.0,
                    horizontalAccuracy: 10,
                    placeName: $0
                )
            }
            let session = Session(
                id: UUID(),
                name: entry.name,
                note: entry.note,
                createdAt: createdAt,
                firstLocation: location
            )
            try session.insert(db)

            for i in 0..<entry.photoCount {
                let photoId = UUID()
                let capturedAt = createdAt.addingTimeInterval(TimeInterval(i) * 60)
                let photo = Photo(
                    id: photoId,
                    sessionId: session.id,
                    fileName: "\(photoId.uuidString).heic",
                    kind: .photo,
                    capturedAt: capturedAt,
                    location: location
                )
                try photo.insert(db)
            }
        }
    }
}

/// `FileOps`의 in-memory 구현 (preview 전용). 모든 메서드가 dictionary lookup 또는 noop.
/// 실제 image bytes를 안 들고 있으므로 `readFinal` / `readThumb`은 seed된 데이터가 없는
/// 한 `fileNotFound`로 throw — ThumbnailView 같은 consumer는 placeholder fallback.
final class MemoryFileOps: FileOps, @unchecked Sendable {
    enum Error: Swift.Error, Sendable {
        case fileNotFound
    }

    private let lock = NSLock()
    private var staging: [String: Data] = [:]
    private var final: [String: Data] = [:]
    private var thumbs: [String: Data] = [:]

    func writeStaging(fileName: String, data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        staging[fileName] = data
    }

    func moveStagingToFinal(fileName: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard let data = staging.removeValue(forKey: fileName) else {
            throw Error.fileNotFound
        }
        final[fileName] = data
    }

    func removeStaging(fileName: String) throws {
        lock.lock(); defer { lock.unlock() }
        staging.removeValue(forKey: fileName)
    }

    func removeFinal(fileName: String) throws {
        lock.lock(); defer { lock.unlock() }
        final.removeValue(forKey: fileName)
    }

    func stagingExists(fileName: String) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        return staging[fileName] != nil
    }

    func finalExists(fileName: String) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        return final[fileName] != nil
    }

    func enumerateFinal() throws -> [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(final.keys)
    }

    func readFinal(fileName: String) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard let data = final[fileName] else {
            throw Error.fileNotFound
        }
        return data
    }

    func writeThumb(fileName: String, data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        thumbs[fileName] = data
    }

    func readThumb(fileName: String) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard let data = thumbs[fileName] else {
            throw Error.fileNotFound
        }
        return data
    }

    func removeThumb(fileName: String) throws {
        lock.lock(); defer { lock.unlock() }
        thumbs.removeValue(forKey: fileName)
    }

    func enumerateThumb() throws -> [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(thumbs.keys)
    }
}
#endif
