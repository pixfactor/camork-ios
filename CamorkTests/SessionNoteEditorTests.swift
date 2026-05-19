import Testing
import Foundation
import GRDB
@testable import Camork

@Suite("SessionNoteEditor")
struct SessionNoteEditorTests {

    func makeStorage() async throws -> (MediaStorage, DatabaseQueue) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cachesDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let db = try DatabaseQueue(configuration: CamorkDatabase.makeConfiguration())
        try Migrations.makeMigrator().migrate(db)
        let fs = try MediaFileSystem(root: dir, cachesRoot: cachesDir)
        return (MediaStorage(db: db, fs: fs), db)
    }

    @Test("round-trip: note 문자열이 Session row에 그대로 반영됨 (trim 없음)")
    func updateAndReload() async throws {
        let (storage, db) = try await makeStorage()
        let photo = try await storage.saveCapture(makePayload())
        let editor = SessionNoteEditor(mediaStorage: storage)

        // SessionNoteEditor는 note를 trim하지 않음 — 양쪽 공백/빈 줄도 그대로 저장
        try await editor.update(sessionId: photo.sessionId, note: "  누수 확인 필요  ")

        let session = try await db.read { db in
            try Session.fetchOne(db, key: photo.sessionId.uuidString)
        }
        #expect(session?.note == "  누수 확인 필요  ")
    }

    @Test("notFound: 존재하지 않는 sessionId + deleted session 둘 다 notFound throw")
    func notFound() async throws {
        let (storage, db) = try await makeStorage()
        let editor = SessionNoteEditor(mediaStorage: storage)

        await #expect(throws: SessionNoteEditor.Error.notFound) {
            try await editor.update(sessionId: UUID(), note: "test")
        }

        let photo = try await storage.saveCapture(makePayload())
        try await db.write { db in
            try db.execute(
                sql: "UPDATE Session SET deletedAt = ? WHERE id = ?",
                arguments: [Int64(9_999), photo.sessionId.uuidString]
            )
        }
        await #expect(throws: SessionNoteEditor.Error.notFound) {
            try await editor.update(sessionId: photo.sessionId, note: "test")
        }
    }

    @Test("clear: note = nil 만이 메모를 제거 (empty string은 보존)")
    func clearToNil() async throws {
        let (storage, db) = try await makeStorage()
        let photo = try await storage.saveCapture(makePayload())
        let editor = SessionNoteEditor(mediaStorage: storage)

        try await editor.update(sessionId: photo.sessionId, note: "초기 메모")
        try await editor.update(sessionId: photo.sessionId, note: nil)

        let session = try await db.read { db in
            try Session.fetchOne(db, key: photo.sessionId.uuidString)
        }
        #expect(session?.note == nil)
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
