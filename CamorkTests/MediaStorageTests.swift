import Testing
import Foundation
import GRDB
@testable import Camork

@Suite("MediaStorage")
struct MediaStorageTests {

    // MARK: - Setup helpers

    func makeStorageReal() async throws -> (MediaStorage, DatabaseQueue, URL) {
        let dir = tempDir()
        let db = try DatabaseQueue(configuration: CamorkDatabase.makeConfiguration())
        try Migrations.makeMigrator().migrate(db)
        let fs = try MediaFileSystem(root: dir)
        let storage = MediaStorage(db: db, fs: fs)
        return (storage, db, dir)
    }

    func makeStorage(fs: any FileOps) async throws -> (MediaStorage, DatabaseQueue) {
        let db = try DatabaseQueue(configuration: CamorkDatabase.makeConfiguration())
        try Migrations.makeMigrator().migrate(db)
        let storage = MediaStorage(db: db, fs: fs)
        return (storage, db)
    }

    // MARK: - Happy path

    @Test("첫 saveCapture — 새 Session + Photo 1건, 파일 final/ 존재")
    func firstCapture() async throws {
        let (storage, db, dir) = try await makeStorageReal()
        let photo = try await storage.saveCapture(
            makePayload(at: Date(timeIntervalSince1970: 1_700_000_000), location: nil)
        )

        let counts = try await db.read { db -> (Int, Int) in
            let p = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Photo") ?? 0
            let s = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Session") ?? 0
            return (p, s)
        }
        #expect(counts.0 == 1)
        #expect(counts.1 == 1)

        let onDisk = try MediaFileSystem(root: dir)
        #expect(try onDisk.finalExists(fileName: photo.fileName))
    }

    @Test("연속 saveCapture — 같은 자리 5초 간격이면 같은 세션에 누적")
    func continueSession() async throws {
        let (storage, db, _) = try await makeStorageReal()
        let loc = LocationSnapshot(latitude: 37.5, longitude: 127.0, horizontalAccuracy: 10, placeName: nil)
        let p1 = try await storage.saveCapture(
            makePayload(at: Date(timeIntervalSince1970: 0), location: loc)
        )
        let p2 = try await storage.saveCapture(
            makePayload(at: Date(timeIntervalSince1970: 5), location: loc)
        )
        #expect(p1.sessionId == p2.sessionId)
        let sessionCount = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Session") ?? 0
        }
        #expect(sessionCount == 1)
    }

    // MARK: - Failure matrix 4 buckets

    @Test("Failure: staging write fail — staging cleanup best-effort + throw")
    func failureStagingWrite() async throws {
        let fakeFs = FakeFileOps(failOn: .writeStaging)
        let (storage, db) = try await makeStorage(fs: fakeFs)

        await #expect(throws: FakeFileOpsError.self) {
            _ = try await storage.saveCapture(makePayload())
        }

        #expect(fakeFs.stagingCleanupCount == 1)
        let photoCount = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Photo") ?? 0
        }
        #expect(photoCount == 0)
    }

    @Test("Failure: mv fail — staging cleanup + abort")
    func failureMv() async throws {
        let fakeFs = FakeFileOps(failOn: .moveStagingToFinal)
        let (storage, db) = try await makeStorage(fs: fakeFs)

        await #expect(throws: FakeFileOpsError.self) {
            _ = try await storage.saveCapture(makePayload())
        }

        #expect(fakeFs.stagingCleanupCount == 1)
        #expect(fakeFs.finalRemoveCount == 0)
        let photoCount = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Photo") ?? 0
        }
        #expect(photoCount == 0)
    }

    @Test("Failure: DB commit fail (beforeDBCommit hook throw) — final 파일 best-effort 삭제")
    func failureCommit() async throws {
        let fakeFs = FakeFileOps()
        let (storage, db) = try await makeStorage(fs: fakeFs)

        struct SyntheticDBError: Error {}
        await storage.installTestHook(beforeDBCommit: { throw SyntheticDBError() })

        await #expect(throws: SyntheticDBError.self) {
            _ = try await storage.saveCapture(makePayload())
        }

        #expect(fakeFs.finalRemoveCount == 1)
        let counts = try await db.read { db -> (Int, Int) in
            let p = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Photo") ?? 0
            let s = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Session") ?? 0
            return (p, s)
        }
        #expect(counts.0 == 0)
        #expect(counts.1 == 0)
    }

    @Test("Orphan reaper: 여러 orphan 파일을 한 번에 정리, legitimate 파일은 보존")
    func reaperOrphan() async throws {
        let (storage, _, dir) = try await makeStorageReal()
        let legit = try await storage.saveCapture(makePayload())

        let onDisk = try MediaFileSystem(root: dir)
        let orphans = ["orphan-a.heic", "orphan-b.heic", "orphan-c.heic"]
        for name in orphans {
            try onDisk.writeStaging(fileName: name, data: Data([1]))
            try onDisk.moveStagingToFinal(fileName: name)
        }

        try await storage.runReaper()

        for name in orphans {
            #expect(try !onDisk.finalExists(fileName: name), "\(name) 제거되어야 함")
        }
        #expect(try onDisk.finalExists(fileName: legit.fileName))
    }

    @Test("Failure matrix bucket #4: mv 후 commit 직전 crash 시뮬 — UUID-named final orphan을 reaper가 정리, legitimate 보존")
    func failureCrashAfterMv() async throws {
        let (storage, _, dir) = try await makeStorageReal()
        let legit = try await storage.saveCapture(makePayload())

        // 진짜 saveCapture가 mv까지 끝낸 직후 crash한 상태 재현 — UUID-named heic 파일만
        // 남기고 DB row는 없음 (ADR #3 4번째 bucket).
        let onDisk = try MediaFileSystem(root: dir)
        let orphanFile = "\(UUID().uuidString).heic"
        try onDisk.writeStaging(fileName: orphanFile, data: Data([42]))
        try onDisk.moveStagingToFinal(fileName: orphanFile)

        #expect(try onDisk.finalExists(fileName: orphanFile))
        #expect(try onDisk.finalExists(fileName: legit.fileName))

        // 앱 재시작 시 reaper 호출
        try await storage.runReaper()

        #expect(try !onDisk.finalExists(fileName: orphanFile))
        #expect(try onDisk.finalExists(fileName: legit.fileName))
    }

    // MARK: - manualFlag captured semantics

    @Test("Race: captured manualFlag == false, beforeDBCommit hook에서 markPending — 1st save가 wipe 안 함")
    func raceManualFlagSetDuringInFlight() async throws {
        let (storage, _, _) = try await makeStorageReal()
        await storage.installTestHook(beforeDBCommit: { [storage] in
            await storage.markPendingNewSession()
        })

        _ = try await storage.saveCapture(makePayload())

        // beforeDBCommit hook이 in-flight 도중 set한 flag를 captured manualFlag==false인
        // 1st save가 wipe하지 않아야 함.
        #expect(await storage.isPendingNewSession() == true)
    }

    @Test("Consumed: manualFlag true 1st save 후 consumed flag clear — 2nd save는 captured=false로 continue")
    func consumedFlagClearAfterTrueSave() async throws {
        let (storage, db, _) = try await makeStorageReal()
        let loc = LocationSnapshot(latitude: 37.5, longitude: 127.0, horizontalAccuracy: 10, placeName: nil)

        await storage.markPendingNewSession()
        let p1 = try await storage.saveCapture(
            makePayload(at: Date(timeIntervalSince1970: 0), location: loc)
        )
        // p1: manualFlag captured=true → newSession override + post-save wipe → state=false
        #expect(await storage.isPendingNewSession() == false)

        let p2 = try await storage.saveCapture(
            makePayload(at: Date(timeIntervalSince1970: 1), location: loc)
        )
        // p2: captured=false, 1초 + 같은 자리 → policy continueSession
        #expect(p1.sessionId == p2.sessionId)
        let sessionCount = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Session") ?? 0
        }
        #expect(sessionCount == 1)
    }

    // MARK: - Latest photo + raw data load (Phase 3.2)

    @Test("fetchLatestPhoto: 가장 최근 capturedAt의 Photo 반환")
    func fetchLatestPhotoOrdering() async throws {
        let (storage, _, _) = try await makeStorageReal()
        let loc = LocationSnapshot(latitude: 0, longitude: 0, horizontalAccuracy: 10, placeName: nil)
        _ = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_000), location: loc))
        let p2 = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 2_000), location: loc))

        let latest = try await storage.fetchLatestPhoto()
        #expect(latest?.id == p2.id)
    }

    @Test("fetchLatestPhoto: 저장된 Photo가 없으면 nil")
    func fetchLatestPhotoEmpty() async throws {
        let (storage, _, _) = try await makeStorageReal()
        let latest = try await storage.fetchLatestPhoto()
        #expect(latest == nil)
    }

    @Test("loadPhotoData: 방금 저장한 capture Photo로 Data 반환 (round-trip)")
    func loadPhotoDataRoundTrip() async throws {
        let (storage, _, _) = try await makeStorageReal()
        let payload = makePayload()
        let photo = try await storage.saveCapture(payload)

        let data = try await storage.loadPhotoData(for: photo)
        #expect(data == payload.data)
    }

    @Test("loadPhotoData: canonical fileName이지만 파일이 없으면 error throw (silent empty Data 금지)")
    func loadPhotoDataMissingThrows() async throws {
        let (storage, _, _) = try await makeStorageReal()
        let id = UUID()
        let phantom = Photo(
            id: id,
            sessionId: UUID(),
            fileName: "\(id.uuidString).heic",
            kind: .photo,
            capturedAt: Date(timeIntervalSince1970: 0)
        )

        await #expect(throws: (any Swift.Error).self) {
            _ = try await storage.loadPhotoData(for: phantom)
        }
    }

    @Test("loadPhotoData: path traversal fileName → MediaStorage.Error.invalidFileName")
    func loadPhotoDataPathTraversalRejected() async throws {
        let (storage, _, _) = try await makeStorageReal()
        let traversal = Photo(
            id: UUID(),
            sessionId: UUID(),
            fileName: "../../etc/passwd",
            kind: .photo,
            capturedAt: Date(timeIntervalSince1970: 0)
        )
        await #expect(throws: MediaStorage.Error.invalidFileName) {
            _ = try await storage.loadPhotoData(for: traversal)
        }
    }

    @Test("loadPhotoData: photo.id와 fileName UUID 불일치 → MediaStorage.Error.invalidFileName")
    func loadPhotoDataMismatchedUUIDRejected() async throws {
        let (storage, _, _) = try await makeStorageReal()
        let mismatched = Photo(
            id: UUID(),
            sessionId: UUID(),
            fileName: "\(UUID().uuidString).heic",  // canonical 구조지만 다른 UUID
            kind: .photo,
            capturedAt: Date(timeIntervalSince1970: 0)
        )
        await #expect(throws: MediaStorage.Error.invalidFileName) {
            _ = try await storage.loadPhotoData(for: mismatched)
        }
    }

    // MARK: - Codec / Decoding contracts

    @Test("Date codec: capturedAt이 SQLite INTEGER로 저장됨 (ADR #11)")
    func capturedAtIntegerStorage() async throws {
        let (storage, db, _) = try await makeStorageReal()
        _ = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_700_000_000)))

        let typeofCol = try await db.read { db in
            try String.fetchOne(db, sql: "SELECT typeof(capturedAt) FROM Photo LIMIT 1")
        }
        #expect(typeofCol == "integer")
    }

    @Test("PhotoDecodingError.invalidUUID: corrupt UUID 행을 fetch 시 throw (INSERT 우회 — UUID format 제약 없음)")
    func corruptUUIDThrows() async throws {
        let (_, db, _) = try await makeStorageReal()
        let sessionId = UUID().uuidString

        try await db.write { db in
            try db.execute(
                sql: "INSERT INTO Session (id, name, createdAt) VALUES (?, 'test', 0)",
                arguments: [sessionId]
            )
            try db.execute(
                sql: """
                    INSERT INTO Photo (id, sessionId, fileName, kind, capturedAt)
                    VALUES ('GARBAGE-NOT-UUID', ?, 'a.heic', 'photo', 0)
                    """,
                arguments: [sessionId]
            )
        }

        await #expect(throws: PhotoDecodingError.self) {
            _ = try await db.read { db in
                try Photo.fetchOne(db, sql: "SELECT * FROM Photo")
            }
        }
    }

    @Test("PhotoDecodingError.invalidMediaKind: 알 수 없는 kind 값에 대해 Photo init(row:) throw (CHECK 제약 우회를 위해 crafted SELECT)")
    func corruptMediaKindThrows() async throws {
        // CHECK (kind IN ('photo'))로 INSERT는 불가 → SELECT로 가짜 Row를 즉석 합성.
        // Photo의 컬럼 13개를 모두 명명해야 init(row:)이 정상 진입.
        let (_, db, _) = try await makeStorageReal()
        let pid = UUID().uuidString
        let sid = UUID().uuidString

        await #expect(throws: PhotoDecodingError.self) {
            _ = try await db.read { db in
                let row = try Row.fetchOne(db, sql: """
                    SELECT
                        ? AS id,
                        ? AS sessionId,
                        'a.heic' AS fileName,
                        NULL AS thumbnailFileName,
                        'video' AS kind,
                        0 AS capturedAt,
                        NULL AS lat,
                        NULL AS lon,
                        NULL AS horizontalAccuracy,
                        NULL AS placeName,
                        NULL AS exifJson,
                        NULL AS note,
                        NULL AS deletedAt
                    """, arguments: [pid, sid])
                guard let row else { return }
                _ = try Photo(row: row)
            }
        }
    }
}

// MARK: - File-scope helpers

private func makePayload(
    at capturedAt: Date = Date(timeIntervalSince1970: 0),
    location: LocationSnapshot? = nil
) -> PhotoCapturePayload {
    PhotoCapturePayload(
        data: Data([0xFF, 0xD8, 0xFF, 0xE0]),
        capturedAt: capturedAt,
        location: location,
        exif: nil
    )
}

private func tempDir() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
}
