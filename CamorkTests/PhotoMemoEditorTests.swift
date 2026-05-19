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
}

private func makePayload() -> PhotoCapturePayload {
    PhotoCapturePayload(
        data: Data([0xFF, 0xD8, 0xFF, 0xE0]),
        capturedAt: Date(timeIntervalSince1970: 0),
        location: nil,
        exif: nil
    )
}
