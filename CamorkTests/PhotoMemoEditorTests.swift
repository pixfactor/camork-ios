import Testing
import Foundation
import GRDB
@testable import Camork

@Suite("PhotoMemoEditor")
struct PhotoMemoEditorTests {

    func makeStorage() async throws -> MediaStorage {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let db = try DatabaseQueue(configuration: CamorkDatabase.makeConfiguration())
        try Migrations.makeMigrator().migrate(db)
        let fs = try MediaFileSystem(root: dir)
        return MediaStorage(db: db, fs: fs)
    }

    @Test("note update 후 fetchPhoto에서 동일 값 반환")
    func updateAndReload() async throws {
        let storage = try await makeStorage()
        let editor = PhotoMemoEditor(mediaStorage: storage)
        let photo = try await storage.saveCapture(makePayload())

        try await editor.update(photoId: photo.id, note: "도산공원 점검 — 누수 확인 필요")

        let fetched = try await storage.fetchPhoto(id: photo.id)
        #expect(fetched?.note == "도산공원 점검 — 누수 확인 필요")
    }

    @Test("note = nil로 설정해 메모 clear")
    func clearToNil() async throws {
        let storage = try await makeStorage()
        let editor = PhotoMemoEditor(mediaStorage: storage)
        let photo = try await storage.saveCapture(makePayload())

        try await editor.update(photoId: photo.id, note: "초기 메모")
        try await editor.update(photoId: photo.id, note: nil)

        let fetched = try await storage.fetchPhoto(id: photo.id)
        #expect(fetched?.note == nil)
    }

    @Test("존재하지 않는 photoId → PhotoMemoEditor.Error.notFound throw")
    func notFound() async throws {
        let storage = try await makeStorage()
        let editor = PhotoMemoEditor(mediaStorage: storage)

        await #expect(throws: PhotoMemoEditor.Error.notFound) {
            try await editor.update(photoId: UUID(), note: "doesn't matter")
        }
    }

    @Test("deletedAt 설정된 photo → PhotoMemoEditor.Error.notFound (fetchPhoto의 deletedAt 필터 경유)")
    func deletedPhotoMapsToNotFound() async throws {
        // PhotoMemoEditor가 MediaStorage.fetchPhoto를 호출하므로 fetchPhoto의 deletedAt 필터
        // 강화(Phase 1.4)가 editor에도 자연스럽게 전달되는지 확인. db에 직접 접근해서
        // deletedAt을 set해야 하므로 makeStorage() 헬퍼 대신 인라인으로 db까지 보관.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let db = try DatabaseQueue(configuration: CamorkDatabase.makeConfiguration())
        try Migrations.makeMigrator().migrate(db)
        let fs = try MediaFileSystem(root: dir)
        let storage = MediaStorage(db: db, fs: fs)
        let editor = PhotoMemoEditor(mediaStorage: storage)
        let photo = try await storage.saveCapture(makePayload())

        try await db.write { db in
            try db.execute(
                sql: "UPDATE Photo SET deletedAt = ? WHERE id = ?",
                arguments: [Int64(9_999), photo.id.uuidString]
            )
        }

        await #expect(throws: PhotoMemoEditor.Error.notFound) {
            try await editor.update(photoId: photo.id, note: "should fail")
        }
    }
}

private func makePayload() -> PhotoCapturePayload {
    PhotoCapturePayload(
        data: Data([0xFF, 0xD8, 0xFF, 0xE0]),
        capturedAt: Date(timeIntervalSince1970: 0),
        location: nil,
        exif: nil
    )
}
