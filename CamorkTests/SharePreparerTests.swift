import Foundation
import GRDB
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import Camork

@Suite("SharePreparer")
struct SharePreparerTests {
    @Test("prepare: 단일 photo + location ON + time ON → tmp/Share/<UUID>/photo-0.heic + 자동 텍스트")
    func singlePhotoBothOn() async throws {
        let fixture = try await makeFixture()

        let bundle = try await fixture.preparer.prepare(
            photos: [fixture.photo],
            session: fixture.session,
            includeLocation: true,
            includeTime: true
        )

        #expect(bundle.fileURLs.count == 1)
        #expect(bundle.fileURLs[0].lastPathComponent == "photo-0.heic")
        #expect(bundle.fileURLs[0].path.hasPrefix(bundle.tempDir.path))
        #expect(FileManager.default.fileExists(atPath: bundle.fileURLs[0].path))
        #expect(bundle.autoText == "[현장 점검] · 2026-05-19 14:30 · 도산공원 — 사진 1장")
    }

    @Test("prepare: 다중 photo")
    func multiplePhotos() async throws {
        let fixture = try await makeFixture()
        let second = try await fixture.savePhoto()

        let bundle = try await fixture.preparer.prepare(
            photos: [fixture.photo, second],
            session: fixture.session,
            includeLocation: true,
            includeTime: true
        )

        #expect(bundle.fileURLs.map(\.lastPathComponent) == ["photo-0.heic", "photo-1.heic"])
        #expect(bundle.fileURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(bundle.autoText.hasSuffix("사진 2장"))
    }

    @Test("자동 텍스트 형식: location/time 토글 조합 4종")
    func autoTextVariants() async throws {
        let fixture = try await makeFixture()

        let both = try await fixture.preparer.prepare(
            photos: [fixture.photo],
            session: fixture.session,
            includeLocation: true,
            includeTime: true
        )
        let noLocation = try await fixture.preparer.prepare(
            photos: [fixture.photo],
            session: fixture.session,
            includeLocation: false,
            includeTime: true
        )
        let noTime = try await fixture.preparer.prepare(
            photos: [fixture.photo],
            session: fixture.session,
            includeLocation: true,
            includeTime: false
        )
        let neither = try await fixture.preparer.prepare(
            photos: [fixture.photo],
            session: fixture.session,
            includeLocation: false,
            includeTime: false
        )

        #expect(both.autoText == "[현장 점검] · 2026-05-19 14:30 · 도산공원 — 사진 1장")
        #expect(noLocation.autoText == "[현장 점검] · 2026-05-19 14:30 — 사진 1장")
        #expect(noTime.autoText == "[현장 점검] · 도산공원 — 사진 1장")
        #expect(neither.autoText == "[현장 점검] — 사진 1장")
    }

    @Test("위치 OFF → ShareSanitizer가 GPS strip한 사본 작성")
    func locationOffSanitizes() async throws {
        let fixture = try await makeFixture()

        let bundle = try await fixture.preparer.prepare(
            photos: [fixture.photo],
            session: fixture.session,
            includeLocation: false,
            includeTime: true
        )
        let output = try Data(contentsOf: bundle.fileURLs[0])

        #expect(imageProperties(of: output)[kCGImagePropertyGPSDictionary as String] == nil)
    }

    @Test("cleanup: ShareBundle.tempDir 삭제 시 파일 사라짐")
    func cleanupRemoves() async throws {
        let fixture = try await makeFixture()
        let bundle = try await fixture.preparer.prepare(
            photos: [fixture.photo],
            session: fixture.session,
            includeLocation: true,
            includeTime: true
        )
        #expect(FileManager.default.fileExists(atPath: bundle.tempDir.path))

        await fixture.preparer.cleanup(bundle)

        #expect(!FileManager.default.fileExists(atPath: bundle.tempDir.path))
    }

    @Test("cleanupExpired: 24h 이상 orphan만 정리, 최근 보존")
    func cleanupExpiredAge() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tempRoot = tempDir()
        let shareRoot = tempRoot
            .appendingPathComponent("Camork", isDirectory: true)
            .appendingPathComponent("Share", isDirectory: true)
        let oldDir = shareRoot.appendingPathComponent("old", isDirectory: true)
        let recentDir = shareRoot.appendingPathComponent("recent", isDirectory: true)
        try FileManager.default.createDirectory(at: oldDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: recentDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-25 * 60 * 60)],
            ofItemAtPath: oldDir.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-60 * 60)],
            ofItemAtPath: recentDir.path
        )

        let storage = try await makeStorage().storage
        let preparer = SharePreparer(
            mediaStorage: storage,
            temporaryRoot: tempRoot,
            now: { now }
        )

        await preparer.cleanupExpired()

        #expect(!FileManager.default.fileExists(atPath: oldDir.path))
        #expect(FileManager.default.fileExists(atPath: recentDir.path))
    }
}

// MARK: - Fixtures

private struct ShareFixture {
    let storage: MediaStorage
    let preparer: SharePreparer
    let session: Session
    let photo: Photo
    let capturedAt: Date

    func savePhoto() async throws -> Photo {
        try await storage.saveCapture(
            PhotoCapturePayload(
                data: makeJPEGData(),
                capturedAt: capturedAt,
                location: makeLocation(),
                exif: nil
            )
        )
    }
}

private func makeFixture() async throws -> ShareFixture {
    let capturedAt = localDate(year: 2026, month: 5, day: 19, hour: 14, minute: 30)
    let storage = try await makeStorage().storage
    let photo = try await storage.saveCapture(
        PhotoCapturePayload(
            data: makeJPEGData(),
            capturedAt: capturedAt,
            location: makeLocation(),
            exif: nil
        )
    )
    let session = Session(
        id: UUID(),
        name: "현장 점검",
        createdAt: capturedAt,
        firstLocation: makeLocation()
    )
    let preparer = SharePreparer(mediaStorage: storage, temporaryRoot: tempDir())
    return ShareFixture(
        storage: storage,
        preparer: preparer,
        session: session,
        photo: photo,
        capturedAt: capturedAt
    )
}

private func makeStorage() async throws -> (storage: MediaStorage, fs: FakeFileOps) {
    let db = try DatabaseQueue(configuration: CamorkDatabase.makeConfiguration())
    try Migrations.makeMigrator().migrate(db)
    let fs = FakeFileOps()
    return (MediaStorage(db: db, fs: fs), fs)
}

private func makeLocation() -> LocationSnapshot {
    LocationSnapshot(
        latitude: 37.5219,
        longitude: 127.0227,
        horizontalAccuracy: 10,
        placeName: "도산공원"
    )
}

private func localDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int
) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = .current
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return components.date!
}

private func tempDir() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
}

private func makeJPEGData() -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0
    let renderer = UIGraphicsImageRenderer(
        size: CGSize(width: 16, height: 12),
        format: format
    )
    let image = renderer.image { _ in
        UIColor.systemBlue.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: 16, height: 12))
    }

    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(
        output,
        UTType.jpeg.identifier as CFString,
        1,
        nil
    )!
    let gps: [String: Any] = [
        kCGImagePropertyGPSLatitude as String: 37.5219,
        kCGImagePropertyGPSLatitudeRef as String: "N",
        kCGImagePropertyGPSLongitude as String: 127.0227,
        kCGImagePropertyGPSLongitudeRef as String: "E"
    ]
    let properties: [CFString: Any] = [
        kCGImagePropertyGPSDictionary: gps
    ]

    CGImageDestinationAddImage(destination, image.cgImage!, properties as CFDictionary)
    precondition(CGImageDestinationFinalize(destination))
    return output as Data
}

private func imageProperties(of data: Data) -> [String: Any] {
    let source = CGImageSourceCreateWithData(data as CFData, nil)!
    return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [String: Any]
}
