import Testing
import Foundation
import GRDB
@testable import Camork

@Suite("SessionInfoEditor")
struct SessionInfoEditorTests {

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

    @Test("round-trip: trim된 name + note가 단일 transaction으로 함께 반영")
    func updateAndReload() async throws {
        let (storage, db) = try await makeStorage()
        let photo = try await storage.saveCapture(makePayload())
        let editor = SessionInfoEditor(mediaStorage: storage)

        try await editor.update(
            sessionId: photo.sessionId,
            name: "  도산공원 점검  ",
            note: "외벽 균열 점검 시작"
        )

        let session = try await db.read { db in
            try Session.fetchOne(db, key: photo.sessionId.uuidString)
        }
        #expect(session?.name == "도산공원 점검")
        #expect(session?.note == "외벽 균열 점검 시작")
    }

    @Test("note=nil 만이 메모를 clear (SessionNoteEditor와 동일 정책)")
    func clearNote() async throws {
        let (storage, db) = try await makeStorage()
        let photo = try await storage.saveCapture(makePayload())
        let editor = SessionInfoEditor(mediaStorage: storage)

        try await editor.update(sessionId: photo.sessionId, name: "test", note: "메모")
        try await editor.update(sessionId: photo.sessionId, name: "test", note: nil)

        let session = try await db.read { db in
            try Session.fetchOne(db, key: photo.sessionId.uuidString)
        }
        #expect(session?.note == nil)
    }

    @Test("note=빈 문자열은 그대로 저장 (사용자 의도 보존)")
    func emptyStringNotePreserved() async throws {
        let (storage, db) = try await makeStorage()
        let photo = try await storage.saveCapture(makePayload())
        let editor = SessionInfoEditor(mediaStorage: storage)

        try await editor.update(sessionId: photo.sessionId, name: "test", note: "")

        let session = try await db.read { db in
            try Session.fetchOne(db, key: photo.sessionId.uuidString)
        }
        #expect(session?.note == "")
    }

    @Test("emptyName: trim 후 빈 이름은 DB 도달 전에 차단 — 메모도 같이 commit 되면 안 됨")
    func emptyNameRejectedBeforeWrite() async throws {
        let (storage, db) = try await makeStorage()
        let photo = try await storage.saveCapture(makePayload())
        let originalName = try await db.read { db in
            try Session.fetchOne(db, key: photo.sessionId.uuidString)?.name
        }
        let editor = SessionInfoEditor(mediaStorage: storage)

        await #expect(throws: SessionInfoEditor.Error.emptyName) {
            try await editor.update(
                sessionId: photo.sessionId,
                name: "   ",
                note: "이 메모는 저장되면 안 됨"
            )
        }

        // 이름이 reject되었으므로 메모도 함께 절대로 저장되지 않아야 한다.
        let session = try await db.read { db in
            try Session.fetchOne(db, key: photo.sessionId.uuidString)
        }
        #expect(session?.name == originalName)
        #expect(session?.note == nil)
    }

    @Test("notFound: 미존재 + soft-deleted 모두 notFound")
    func notFound() async throws {
        let (storage, db) = try await makeStorage()
        let editor = SessionInfoEditor(mediaStorage: storage)

        await #expect(throws: SessionInfoEditor.Error.notFound) {
            try await editor.update(sessionId: UUID(), name: "test", note: nil)
        }

        let photo = try await storage.saveCapture(makePayload())
        try await db.write { db in
            try db.execute(
                sql: "UPDATE Session SET deletedAt = ? WHERE id = ?",
                arguments: [Int64(9_999), photo.sessionId.uuidString]
            )
        }
        await #expect(throws: SessionInfoEditor.Error.notFound) {
            try await editor.update(sessionId: photo.sessionId, name: "test", note: nil)
        }
    }

    @Test("두 필드 commit 원자성: name UPDATE 후 동일 transaction에서 note도 반영")
    func atomicCommit() async throws {
        let (storage, db) = try await makeStorage()
        let photo = try await storage.saveCapture(makePayload())
        let editor = SessionInfoEditor(mediaStorage: storage)

        try await editor.update(
            sessionId: photo.sessionId,
            name: "현장 점검 보강",
            note: "외벽 균열 점검 시작\n방수 처리 확인"
        )

        // 단일 SELECT으로 두 컬럼 모두 새 값이어야 — 부분 commit이 아니어야.
        let row = try await db.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT name, note FROM Session WHERE id = ?",
                arguments: [photo.sessionId.uuidString]
            )
        }
        #expect(row?["name"] as String? == "현장 점검 보강")
        #expect(row?["note"] as String? == "외벽 균열 점검 시작\n방수 처리 확인")
    }
}

// MARK: - Helpers

private func makePayload() -> PhotoCapturePayload {
    PhotoCapturePayload(
        data: Data([0xFF, 0xD8, 0xFF, 0xE0]),
        capturedAt: Date(timeIntervalSince1970: 0),
        location: nil,
        exif: nil
    )
}
