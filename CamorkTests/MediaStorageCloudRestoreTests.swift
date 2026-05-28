import Foundation
import GRDB
import Testing
@testable import Camork

@Suite("MediaStorage cloud restore")
struct MediaStorageCloudRestoreTests {
    @Test("Cloud session and photo upsert is idempotent and updates local metadata")
    func upsertMetadata() async throws {
        let db = try DatabaseQueue(configuration: CamorkDatabase.makeConfiguration())
        try Migrations.makeMigrator().migrate(db)
        let storage = MediaStorage(db: db, fs: FakeFileOps())

        let sessionId = UUID()
        let photoId = UUID()
        let initialSession = Session(
            id: sessionId,
            name: "원본",
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let updatedSession = Session(
            id: sessionId,
            name: "수정됨",
            note: "원격 메모",
            createdAt: Date(timeIntervalSince1970: 10),
            firstLocation: LocationSnapshot(
                latitude: 37.0,
                longitude: 127.0,
                horizontalAccuracy: 6,
                placeName: "서울"
            )
        )
        let photo = Photo(
            id: photoId,
            sessionId: sessionId,
            fileName: "\(photoId.uuidString).heic",
            kind: .photo,
            capturedAt: Date(timeIntervalSince1970: 20),
            note: "사진 메모"
        )

        try await storage.upsertCloudSession(initialSession)
        try await storage.upsertCloudSession(updatedSession)
        try await storage.upsertCloudPhotoMetadata(photo)

        let rows = try await storage.fetchExportRows()
        #expect(rows.sessions.count == 1)
        #expect(rows.sessions[0].name == "수정됨")
        #expect(rows.sessions[0].note == "원격 메모")
        #expect(rows.photos.count == 1)
        #expect(rows.photos[0].id == photoId)
        #expect(rows.photos[0].note == "사진 메모")
    }

    @Test("Cloud asset restore writes canonical media once and skips existing originals")
    func restoreOriginalData() async throws {
        let db = try DatabaseQueue(configuration: CamorkDatabase.makeConfiguration())
        try Migrations.makeMigrator().migrate(db)
        let fs = FakeFileOps()
        let storage = MediaStorage(db: db, fs: fs)
        let photoId = UUID()

        let first = try await storage.restoreCloudPhotoData(id: photoId, data: Data([1, 2, 3]))
        let second = try await storage.restoreCloudPhotoData(id: photoId, data: Data([9, 9, 9]))

        #expect(first == true)
        #expect(second == false)
        #expect(try fs.readFinal(fileName: "\(photoId.uuidString).heic") == Data([1, 2, 3]))
    }
}
