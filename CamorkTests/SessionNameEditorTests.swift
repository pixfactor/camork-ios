import Testing
import Foundation
import GRDB
@testable import Camork

@Suite("SessionNameEditor")
struct SessionNameEditorTests {

    func makeStorage() async throws -> (MediaStorage, DatabaseQueue) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let db = try DatabaseQueue(configuration: CamorkDatabase.makeConfiguration())
        try Migrations.makeMigrator().migrate(db)
        let fs = try MediaFileSystem(root: dir)
        return (MediaStorage(db: db, fs: fs), db)
    }

    @Test("round-trip: trim된 name이 Session row에 반영됨")
    func updateAndReload() async throws {
        let (storage, db) = try await makeStorage()
        let photo = try await storage.saveCapture(makePayload())
        let editor = SessionNameEditor(mediaStorage: storage)

        try await editor.update(sessionId: photo.sessionId, name: "  도산공원 점검  ")

        let session = try await db.read { db in
            try Session.fetchOne(db, key: photo.sessionId.uuidString)
        }
        #expect(session?.name == "도산공원 점검")
    }

    @Test("notFound: 존재하지 않는 sessionId + deleted session 둘 다 notFound throw (changesCount == 0)")
    func notFound() async throws {
        let (storage, db) = try await makeStorage()
        let editor = SessionNameEditor(mediaStorage: storage)

        // 1. 존재하지 않는 sessionId
        await #expect(throws: SessionNameEditor.Error.notFound) {
            try await editor.update(sessionId: UUID(), name: "test")
        }

        // 2. deleted session도 notFound (UPDATE의 deletedAt IS NULL 필터)
        let photo = try await storage.saveCapture(makePayload())
        try await db.write { db in
            try db.execute(
                sql: "UPDATE Session SET deletedAt = ? WHERE id = ?",
                arguments: [Int64(9_999), photo.sessionId.uuidString]
            )
        }
        await #expect(throws: SessionNameEditor.Error.notFound) {
            try await editor.update(sessionId: photo.sessionId, name: "test")
        }
    }

    @Test("emptyName: 빈 문자열 / whitespace-only → emptyName throw (DB 도달 전 차단)")
    func emptyName() async throws {
        let (storage, _) = try await makeStorage()
        let photo = try await storage.saveCapture(makePayload())
        let editor = SessionNameEditor(mediaStorage: storage)

        for badName in ["", "   ", "\t\n"] {
            await #expect(throws: SessionNameEditor.Error.emptyName) {
                try await editor.update(sessionId: photo.sessionId, name: badName)
            }
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
