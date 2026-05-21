#if DEBUG
import Foundation
import GRDB
import UIKit

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
        let fs = MemoryFileOps()
        do {
            db = try DatabaseQueue()
            try Migrations.makeMigrator().migrate(db)
            try seedPreviewSampleData(into: db, fs: fs)
        } catch {
            fatalError("DependencyContainer.previewStub() DB setup failed: \(error)")
        }

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

/// Gallery preview용 3개 세션 + 각 세션 2~5장. DEBUG simulator QA가 실제 fade와
/// photo-detail pager를 볼 수 있도록 in-memory final/thumb JPEG도 함께 심는다.
private func seedPreviewSampleData(into db: any DatabaseWriter, fs: MemoryFileOps) throws {
    try db.write { db in
        let now = Date()
        let day: TimeInterval = 24 * 60 * 60
        var imageIndex = 0

        let sessions: [(name: String, note: String?, daysAgo: Double, placeName: String?, photoCount: Int)] = [
            ("테스트입니다", nil, 0, nil, 6),
            ("하단 페이드 점검", "탭 캡슐 뒤로 카드가 부드럽게 사라지는지 확인", 1, "성수동, 서울", 5),
            ("사진 스와이프 점검", "디테일 좌우 넘김과 메모 바 확인", 3, "판교, 성남", 4)
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
                    location: location,
                    note: i == 0 ? "샘플 메모 본문입니다." : nil
                )
                try photo.insert(db)

                let imageData = makePreviewImageData(index: imageIndex)
                try fs.writeStaging(fileName: photo.fileName, data: imageData)
                try fs.moveStagingToFinal(fileName: photo.fileName)
                try fs.writeThumb(fileName: "\(photoId.uuidString).jpg", data: imageData)
                imageIndex += 1
            }
        }
    }
}

private func makePreviewImageData(index: Int) -> Data {
    let size = CGSize(width: 1080, height: 1440)
    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { context in
        let cgContext = context.cgContext
        let palette: [(UIColor, UIColor)] = [
            (.init(red: 0.12, green: 0.07, blue: 0.05, alpha: 1), .init(red: 0.40, green: 0.28, blue: 0.18, alpha: 1)),
            (.init(red: 0.08, green: 0.10, blue: 0.11, alpha: 1), .init(red: 0.46, green: 0.44, blue: 0.36, alpha: 1)),
            (.init(red: 0.07, green: 0.07, blue: 0.09, alpha: 1), .init(red: 0.30, green: 0.22, blue: 0.34, alpha: 1)),
            (.init(red: 0.10, green: 0.08, blue: 0.06, alpha: 1), .init(red: 0.34, green: 0.26, blue: 0.19, alpha: 1))
        ]
        let colors = palette[index % palette.count]

        colors.0.setFill()
        cgContext.fill(CGRect(origin: .zero, size: size))

        cgContext.saveGState()
        cgContext.translateBy(x: size.width * 0.5, y: size.height * 0.48)
        cgContext.rotate(by: CGFloat(index % 5 - 2) * 0.18)
        colors.1.setFill()
        UIBezierPath(roundedRect: CGRect(x: -410, y: -520, width: 820, height: 1040), cornerRadius: 42).fill()

        UIColor.white.withAlphaComponent(0.14).setFill()
        UIBezierPath(roundedRect: CGRect(x: -280, y: -220, width: 560, height: 120), cornerRadius: 22).fill()

        UIColor.black.withAlphaComponent(0.28).setFill()
        UIBezierPath(ovalIn: CGRect(x: -520, y: -700, width: 820, height: 520)).fill()
        cgContext.restoreGState()
    }

    return image.jpegData(compressionQuality: 0.82) ?? Data()
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
