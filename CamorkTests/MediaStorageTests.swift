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
        let fs = try MediaFileSystem(root: dir, cachesRoot: tempDir())
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

        let onDisk = try MediaFileSystem(root: dir, cachesRoot: tempDir())
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

        let onDisk = try MediaFileSystem(root: dir, cachesRoot: tempDir())
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

    @Test("Orphan reaper: Photo row 없는 thumbnail cache 파일 정리, legitimate thumb 보존")
    func reaperThumbnailOrphan() async throws {
        let fakeFs = FakeFileOps()
        let (storage, _) = try await makeStorage(fs: fakeFs)
        let legit = try await storage.saveCapture(makePayload())
        let legitThumb = "\(legit.id.uuidString).jpg"
        let orphanThumb = "\(UUID().uuidString).jpg"
        let malformedThumb = "not-a-photo-id.jpg"
        try fakeFs.writeThumb(fileName: legitThumb, data: Data([0x01]))
        try fakeFs.writeThumb(fileName: orphanThumb, data: Data([0x02]))
        try fakeFs.writeThumb(fileName: malformedThumb, data: Data([0x03]))

        try await storage.runReaper()

        #expect(try fakeFs.readThumb(fileName: legitThumb) == Data([0x01]))
        #expect(throws: FakeFileOpsError.self) {
            _ = try fakeFs.readThumb(fileName: orphanThumb)
        }
        #expect(throws: FakeFileOpsError.self) {
            _ = try fakeFs.readThumb(fileName: malformedThumb)
        }
    }

    @Test("Failure matrix bucket #4: mv 후 commit 직전 crash 시뮬 — UUID-named final orphan을 reaper가 정리, legitimate 보존")
    func failureCrashAfterMv() async throws {
        let (storage, _, dir) = try await makeStorageReal()
        let legit = try await storage.saveCapture(makePayload())

        // 진짜 saveCapture가 mv까지 끝낸 직후 crash한 상태 재현 — UUID-named heic 파일만
        // 남기고 DB row는 없음 (ADR #3 4번째 bucket).
        let onDisk = try MediaFileSystem(root: dir, cachesRoot: tempDir())
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

    // MARK: - Gallery query API (Phase 1.1, Plan C)

    @Test("fetchSessions: 시간순 역방향 (가장 최근이 첫 번째)")
    func fetchSessionsOrdering() async throws {
        let (storage, _, _) = try await makeStorageReal()
        await storage.markPendingNewSession()
        _ = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_000)))
        await storage.markPendingNewSession()
        _ = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 2_000)))
        await storage.markPendingNewSession()
        _ = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 3_000)))

        let sessions = try await storage.fetchSessions()
        #expect(sessions.count == 3)
        #expect(sessions[0].createdAt.timeIntervalSince1970 == 3_000)
        #expect(sessions[2].createdAt.timeIntervalSince1970 == 1_000)
    }

    @Test("fetchSessions: deletedAt non-null 세션 제외")
    func fetchSessionsFiltersDeleted() async throws {
        let (storage, db, _) = try await makeStorageReal()
        let photo = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_000)))

        try await db.write { db in
            try db.execute(
                sql: "UPDATE Session SET deletedAt = ? WHERE id = ?",
                arguments: [Int64(1_500), photo.sessionId.uuidString]
            )
        }

        let sessions = try await storage.fetchSessions()
        #expect(sessions.isEmpty)
    }

    @Test("fetchSessions: 빈 DB → 빈 배열")
    func fetchSessionsEmpty() async throws {
        let (storage, _, _) = try await makeStorageReal()
        let sessions = try await storage.fetchSessions()
        #expect(sessions.isEmpty)
    }

    @Test("fetchPhotos: sessionId 매칭 + 시간순 (오래된 것부터)")
    func fetchPhotosBasic() async throws {
        let (storage, _, _) = try await makeStorageReal()
        let loc = LocationSnapshot(latitude: 0, longitude: 0, horizontalAccuracy: 10, placeName: nil)
        let p1 = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_000), location: loc))
        let p2 = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_100), location: loc))
        let p3 = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_200), location: loc))

        #expect(p1.sessionId == p2.sessionId)  // same session 확인
        #expect(p2.sessionId == p3.sessionId)

        let photos = try await storage.fetchPhotos(sessionId: p1.sessionId)
        #expect(photos.count == 3)
        #expect(photos[0].id == p1.id)
        #expect(photos[1].id == p2.id)
        #expect(photos[2].id == p3.id)
    }

    @Test("fetchPhotos: deletedAt non-null photo 제외")
    func fetchPhotosFiltersDeleted() async throws {
        let (storage, db, _) = try await makeStorageReal()
        let loc = LocationSnapshot(latitude: 0, longitude: 0, horizontalAccuracy: 10, placeName: nil)
        let p1 = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_000), location: loc))
        let p2 = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_100), location: loc))

        try await db.write { db in
            try db.execute(
                sql: "UPDATE Photo SET deletedAt = ? WHERE id = ?",
                arguments: [Int64(1_500), p2.id.uuidString]
            )
        }

        let photos = try await storage.fetchPhotos(sessionId: p1.sessionId)
        #expect(photos.count == 1)
        #expect(photos[0].id == p1.id)
    }

    // MARK: - Gallery preview (Phase 1.2, Plan C)

    @Test("fetchSessionPreview: 5장 photo → totalCount 5 + previewPhotos cap 4 (capturedAt DESC)")
    func sessionPreview4Cap() async throws {
        let (storage, _, _) = try await makeStorageReal()
        let loc = LocationSnapshot(latitude: 0, longitude: 0, horizontalAccuracy: 10, placeName: nil)
        var saved: [Photo] = []
        for i in 0..<5 {
            let p = try await storage.saveCapture(
                makePayload(at: Date(timeIntervalSince1970: Double(i * 10)), location: loc)
            )
            saved.append(p)
        }

        let preview = try await storage.fetchSessionPreview(sessionId: saved[0].sessionId)
        #expect(preview.totalPhotoCount == 5)
        #expect(preview.previewPhotos.count == 4)
        // capturedAt DESC: 가장 최근 저장한 것이 첫 번째
        #expect(preview.previewPhotos[0].id == saved[4].id)
        #expect(preview.previewPhotos[3].id == saved[1].id)
    }

    @Test("fetchSessionPreview: 2장 photo → totalCount 2 + previewPhotos.count 2")
    func sessionPreviewLessThanFour() async throws {
        let (storage, _, _) = try await makeStorageReal()
        let loc = LocationSnapshot(latitude: 0, longitude: 0, horizontalAccuracy: 10, placeName: nil)
        let p1 = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 0), location: loc))
        let p2 = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 10), location: loc))

        let preview = try await storage.fetchSessionPreview(sessionId: p1.sessionId)
        #expect(preview.totalPhotoCount == 2)
        #expect(preview.previewPhotos.count == 2)
        #expect(preview.previewPhotos[0].id == p2.id)
        #expect(preview.previewPhotos[1].id == p1.id)
    }

    @Test("fetchSessionsWithPreview: 세션은 createdAt DESC + 각 preview는 capturedAt DESC, deletedAt 양쪽 제외")
    func sessionsWithPreviewOrdering() async throws {
        let (storage, db, _) = try await makeStorageReal()

        // 세션 A (createdAt 1000) — photo 3개, 그중 1개 deleted
        await storage.markPendingNewSession()
        let a1 = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_000)))
        let a2 = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_010)))
        let a3 = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_020)))
        // 세션 B (createdAt 2000) — photo 2개
        await storage.markPendingNewSession()
        let b1 = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 2_000)))
        let b2 = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 2_010)))
        // 세션 C (createdAt 3000) — deleted
        await storage.markPendingNewSession()
        let c1 = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 3_000)))

        // a2 photo deleted, C session deleted
        try await db.write { db in
            try db.execute(sql: "UPDATE Photo SET deletedAt = ? WHERE id = ?", arguments: [Int64(9_999), a2.id.uuidString])
            try db.execute(sql: "UPDATE Session SET deletedAt = ? WHERE id = ?", arguments: [Int64(9_999), c1.sessionId.uuidString])
        }

        let result = try await storage.fetchSessionsWithPreview()
        // C 제외 → A + B만, B가 최근 (createdAt DESC)
        #expect(result.count == 2)
        #expect(result[0].session.id == b1.sessionId)
        #expect(result[1].session.id == a1.sessionId)

        // B preview: 2장, capturedAt DESC
        #expect(result[0].preview.totalPhotoCount == 2)
        #expect(result[0].preview.previewPhotos.map { $0.id } == [b2.id, b1.id])

        // A preview: a2 deleted 제외, 2장 (a1, a3), totalCount 2
        #expect(result[1].preview.totalPhotoCount == 2)
        #expect(result[1].preview.previewPhotos.map { $0.id } == [a3.id, a1.id])
    }

    @Test("fetchSessionsWithPreview: per-session N+1 회피 — SELECT 호출 카운트 세션 수 무관 (10 세션 × 5 photo)")
    func sessionsWithPreviewNoNPlus1() async throws {
        let counter = SelectCounter()
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            db.trace { event in
                if case .statement(let stmt) = event,
                   stmt.sql.uppercased().contains("SELECT") {
                    counter.increment()
                }
            }
        }
        let db = try DatabaseQueue(configuration: config)
        try Migrations.makeMigrator().migrate(db)
        let fs = try MediaFileSystem(root: dir, cachesRoot: tempDir())
        let storage = MediaStorage(db: db, fs: fs)

        // 10 sessions × 5 photos (markPendingNewSession 으로 강제 분리)
        for i in 0..<10 {
            await storage.markPendingNewSession()
            for j in 0..<5 {
                _ = try await storage.saveCapture(
                    makePayload(at: Date(timeIntervalSince1970: Double(i * 1_000 + j)))
                )
            }
        }

        // Seed 단계의 SELECT는 모두 무시. 측정은 reset 직후 단 한 번의 호출에 대해서만.
        counter.reset()
        _ = try await storage.fetchSessionsWithPreview()
        // invariant: 세션 수에 비례하지 않는 상수 SELECT 호출 (1 SQL window function
        // 또는 2 batched SQL — spec §3.2 양쪽 허용). 10 세션 입력에 비례한 호출은 회귀.
        let measured = counter.value
        #expect((1...2).contains(measured), "expected 1 or 2 SELECT statements (constant w.r.t. session count), got \(measured)")
    }

    @Test("fetchSessionsWithPreview: 세션은 살아있지만 모든 photo가 deleted → previewPhotos []")
    func sessionsWithPreviewAllPhotosDeleted() async throws {
        let (storage, db, _) = try await makeStorageReal()
        let p = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_000)))
        try await db.write { db in
            try db.execute(sql: "UPDATE Photo SET deletedAt = ? WHERE id = ?", arguments: [Int64(9_999), p.id.uuidString])
        }

        let result = try await storage.fetchSessionsWithPreview()
        #expect(result.count == 1)
        #expect(result[0].session.id == p.sessionId)
        #expect(result[0].preview.totalPhotoCount == 0)
        #expect(result[0].preview.previewPhotos.isEmpty)
    }

    @Test("fetchSessionsWithPreview: 한 세션 preview의 photo id는 유니크 + 세션 경계를 넘지 않음")
    func sessionsWithPreviewIdsAreUnique() async throws {
        let (storage, _, _) = try await makeStorageReal()
        // 세션 A: 5장 → preview cap 4
        await storage.markPendingNewSession()
        for i in 0..<5 {
            _ = try await storage.saveCapture(
                makePayload(at: Date(timeIntervalSince1970: Double(1_000 + i)))
            )
        }
        // 세션 B: 6장 → preview cap 4
        await storage.markPendingNewSession()
        for i in 0..<6 {
            _ = try await storage.saveCapture(
                makePayload(at: Date(timeIntervalSince1970: Double(2_000 + i)))
            )
        }

        let result = try await storage.fetchSessionsWithPreview()
        #expect(result.count == 2)

        for entry in result {
            let ids = entry.preview.previewPhotos.map(\.id)
            #expect(ids.count == 4)
            #expect(Set(ids).count == ids.count, "previewPhotos는 한 세션 안에서 photo.id가 중복되면 안 됨")
        }

        let aIds = Set(result.first { $0.session.id == result[0].session.id }!.preview.previewPhotos.map(\.id))
        let bIds = Set(result.first { $0.session.id == result[1].session.id }!.preview.previewPhotos.map(\.id))
        #expect(aIds.isDisjoint(with: bIds), "세션 preview 사이에 같은 photo.id가 양쪽에 동시에 나타나면 안 됨")
    }

    @Test("fetchSessionsWithPreview: capturedAt 동률 4장 → previewPhotos id 중복 없음")
    func sessionsWithPreviewIdsUniqueOnCapturedAtTie() async throws {
        let (storage, _, _) = try await makeStorageReal()
        // 동일 capturedAt 4장 — tie-break 비결정성이 photo 중복으로 새지 않는지 잠금.
        let stamp = Date(timeIntervalSince1970: 5_000)
        await storage.markPendingNewSession()
        for _ in 0..<4 {
            _ = try await storage.saveCapture(makePayload(at: stamp))
        }

        let result = try await storage.fetchSessionsWithPreview()
        #expect(result.count == 1)
        let ids = result[0].preview.previewPhotos.map(\.id)
        #expect(ids.count == 4)
        #expect(Set(ids).count == ids.count, "동률 capturedAt에서도 같은 photo.id가 두 번 들어가면 안 됨")
    }

    // MARK: - fetchPhoto deletedAt strict filter (Phase 1.4, Plan C)

    @Test("fetchPhoto(id:): deletedAt non-null photo는 nil 반환 (caller에 검사 책임 분산 금지)")
    func fetchPhotoFiltersDeleted() async throws {
        let (storage, db, _) = try await makeStorageReal()
        let photo = try await storage.saveCapture(makePayload())

        // 살아있을 때 fetch — 정상 반환
        let alive = try await storage.fetchPhoto(id: photo.id)
        #expect(alive?.id == photo.id)

        // 휴지통 처리 (deletedAt 설정)
        try await db.write { db in
            try db.execute(
                sql: "UPDATE Photo SET deletedAt = ? WHERE id = ?",
                arguments: [Int64(9_999), photo.id.uuidString]
            )
        }
        // deletedAt 설정 후 → nil 반환 (caller에게 deletedAt 검사 책임 분산 안 함)
        let deleted = try await storage.fetchPhoto(id: photo.id)
        #expect(deleted == nil)
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

    // MARK: - Trash (Plan E Batch E1.a — photo-level soft-delete / restore / purge)

    @Test("Plan E E1: fetchDeletedPhotos empty trash → 빈 배열")
    func trashEmpty() async throws {
        let (storage, _, _) = try await makeStorageReal()
        let deleted = try await storage.fetchDeletedPhotos()
        #expect(deleted.isEmpty)
    }

    @Test("Plan E E1: softDeletePhoto → fetchDeletedPhotos에 표시, fetchPhotos 결과에서 제거")
    func softDeleteMovesPhotoToTrash() async throws {
        let (storage, _, _) = try await makeStorageReal()
        let photo = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_000)))

        try await storage.softDeletePhoto(id: photo.id, at: Date(timeIntervalSince1970: 5_000))

        let deleted = try await storage.fetchDeletedPhotos()
        #expect(deleted.count == 1)
        #expect(deleted[0].id == photo.id)
        #expect(deleted[0].deletedAt == Date(timeIntervalSince1970: 5_000))

        let active = try await storage.fetchPhotos(sessionId: photo.sessionId)
        #expect(active.isEmpty)
    }

    @Test("Plan E E1: softDeletePhoto 중복 호출 → photoNotFound (이미 trash 상태)")
    func softDeleteAlreadyDeletedThrows() async throws {
        let (storage, _, _) = try await makeStorageReal()
        let photo = try await storage.saveCapture(makePayload())

        try await storage.softDeletePhoto(id: photo.id, at: Date(timeIntervalSince1970: 5_000))

        await #expect(throws: MediaStorage.Error.photoNotFound) {
            try await storage.softDeletePhoto(id: photo.id, at: Date(timeIntervalSince1970: 6_000))
        }
    }

    @Test("Plan E E1: softDeletePhoto on 미존재 id → photoNotFound")
    func softDeleteMissingPhotoThrows() async throws {
        let (storage, _, _) = try await makeStorageReal()
        await #expect(throws: MediaStorage.Error.photoNotFound) {
            try await storage.softDeletePhoto(id: UUID(), at: Date(timeIntervalSince1970: 5_000))
        }
    }

    @Test("Plan E E1: restorePhoto → fetchPhotos에 복귀, fetchDeletedPhotos에서 제거")
    func restoreFromTrash() async throws {
        let (storage, _, _) = try await makeStorageReal()
        let photo = try await storage.saveCapture(makePayload())
        try await storage.softDeletePhoto(id: photo.id, at: Date(timeIntervalSince1970: 5_000))

        try await storage.restorePhoto(id: photo.id)

        let active = try await storage.fetchPhotos(sessionId: photo.sessionId)
        #expect(active.count == 1)
        #expect(active[0].id == photo.id)
        #expect(active[0].deletedAt == nil)

        let trash = try await storage.fetchDeletedPhotos()
        #expect(trash.isEmpty)
    }

    @Test("Plan E E1: restorePhoto on 정상 상태 photo → photoNotFound")
    func restoreNotInTrashThrows() async throws {
        let (storage, _, _) = try await makeStorageReal()
        let photo = try await storage.saveCapture(makePayload())

        await #expect(throws: MediaStorage.Error.photoNotFound) {
            try await storage.restorePhoto(id: photo.id)
        }
    }

    @Test("Plan E E1: purgePhoto → DB row 제거 + final + thumbnail unlink")
    func purgeRemovesEverything() async throws {
        let fakeFs = FakeFileOps()
        let (storage, db) = try await makeStorage(fs: fakeFs)
        let photo = try await storage.saveCapture(makePayload())
        let thumbName = "\(photo.id.uuidString).jpg"
        try fakeFs.writeThumb(fileName: thumbName, data: Data([0x01]))

        try await storage.softDeletePhoto(id: photo.id, at: Date(timeIntervalSince1970: 5_000))
        try await storage.purgePhoto(id: photo.id)

        let count = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Photo WHERE id = ?", arguments: [photo.id.uuidString]) ?? 0
        }
        #expect(count == 0)
        #expect(try !fakeFs.finalExists(fileName: photo.fileName))
        #expect(throws: FakeFileOpsError.self) {
            _ = try fakeFs.readThumb(fileName: thumbName)
        }
    }

    @Test("Plan E E1: purgePhoto on 정상 상태 photo → photoNotFound, DB/file/thumb 보존")
    func purgeActivePhotoThrowsAndPreservesEverything() async throws {
        let fakeFs = FakeFileOps()
        let (storage, db) = try await makeStorage(fs: fakeFs)
        let photo = try await storage.saveCapture(makePayload())
        let thumbName = "\(photo.id.uuidString).jpg"
        try fakeFs.writeThumb(fileName: thumbName, data: Data([0x01]))

        await #expect(throws: MediaStorage.Error.photoNotFound) {
            try await storage.purgePhoto(id: photo.id)
        }

        let count = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Photo WHERE id = ?", arguments: [photo.id.uuidString]) ?? 0
        }
        #expect(count == 1)
        #expect(try fakeFs.finalExists(fileName: photo.fileName))
        #expect(try fakeFs.readThumb(fileName: thumbName) == Data([0x01]))
    }

    @Test("Plan E E1: purgePhoto on 미존재 id → photoNotFound, 파일 시스템 무영향")
    func purgeMissingPhotoThrows() async throws {
        let fakeFs = FakeFileOps()
        let (storage, _) = try await makeStorage(fs: fakeFs)
        let photo = try await storage.saveCapture(makePayload())

        await #expect(throws: MediaStorage.Error.photoNotFound) {
            try await storage.purgePhoto(id: UUID())
        }

        // 무관한 photo의 final/thumb는 보존
        #expect(try fakeFs.finalExists(fileName: photo.fileName))
    }

    // MARK: - Trash session-level (Plan E Batch E1.b)

    @Test("Plan E E1.b: softDeleteSession cascades photos with same timestamp")
    func softDeleteSessionCascades() async throws {
        let (storage, _, _) = try await makeStorageReal()
        let loc = LocationSnapshot(latitude: 0, longitude: 0, horizontalAccuracy: 10, placeName: nil)
        let p1 = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_000), location: loc))
        let p2 = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_010), location: loc))
        #expect(p1.sessionId == p2.sessionId)

        let stamp = Date(timeIntervalSince1970: 5_000)
        try await storage.softDeleteSession(sessionId: p1.sessionId, at: stamp)

        let deletedSessions = try await storage.fetchDeletedSessions()
        #expect(deletedSessions.count == 1)
        #expect(deletedSessions[0].id == p1.sessionId)
        #expect(deletedSessions[0].deletedAt == stamp)

        let trashedPhotos = try await storage.fetchDeletedPhotos()
        #expect(trashedPhotos.count == 2)
        #expect(trashedPhotos.allSatisfy { $0.deletedAt == stamp })

        // active queries에서 모두 제거
        let activeSessions = try await storage.fetchSessions()
        #expect(activeSessions.isEmpty)
        let activePhotos = try await storage.fetchPhotos(sessionId: p1.sessionId)
        #expect(activePhotos.isEmpty)
    }

    @Test("Plan E E1.b: softDeleteSession은 사전 개별 trash된 사진의 timestamp를 덮지 않음")
    func softDeleteSessionPreservesPriorTrashStamp() async throws {
        let (storage, _, _) = try await makeStorageReal()
        let loc = LocationSnapshot(latitude: 0, longitude: 0, horizontalAccuracy: 10, placeName: nil)
        let p1 = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_000), location: loc))
        let p2 = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_010), location: loc))

        // p1만 먼저 개별 trash
        let earlyStamp = Date(timeIntervalSince1970: 3_000)
        try await storage.softDeletePhoto(id: p1.id, at: earlyStamp)

        // 세션 삭제
        let sessionStamp = Date(timeIntervalSince1970: 5_000)
        try await storage.softDeleteSession(sessionId: p1.sessionId, at: sessionStamp)

        let trashed = try await storage.fetchDeletedPhotos()
        let byId = Dictionary(uniqueKeysWithValues: trashed.map { ($0.id, $0.deletedAt) })
        // p1은 자신의 earlier timestamp 유지, p2는 session stamp
        #expect(byId[p1.id] == earlyStamp)
        #expect(byId[p2.id] == sessionStamp)
    }

    @Test("Plan E E1.b: softDeleteSession on 이미 deleted session → sessionNotFound")
    func softDeleteSessionAlreadyDeletedThrows() async throws {
        let (storage, _, _) = try await makeStorageReal()
        let photo = try await storage.saveCapture(makePayload())
        try await storage.softDeleteSession(sessionId: photo.sessionId, at: Date(timeIntervalSince1970: 5_000))

        await #expect(throws: MediaStorage.Error.sessionNotFound) {
            try await storage.softDeleteSession(sessionId: photo.sessionId, at: Date(timeIntervalSince1970: 6_000))
        }
    }

    @Test("Plan E E1.b: restoreSession은 same-timestamp 사진만 복원, 사전 trash는 그대로")
    func restoreSessionAtomic() async throws {
        let (storage, _, _) = try await makeStorageReal()
        let loc = LocationSnapshot(latitude: 0, longitude: 0, horizontalAccuracy: 10, placeName: nil)
        let p1 = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_000), location: loc))
        let p2 = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_010), location: loc))

        let earlyStamp = Date(timeIntervalSince1970: 3_000)
        try await storage.softDeletePhoto(id: p1.id, at: earlyStamp)
        let sessionStamp = Date(timeIntervalSince1970: 5_000)
        try await storage.softDeleteSession(sessionId: p1.sessionId, at: sessionStamp)

        try await storage.restoreSession(sessionId: p1.sessionId)

        // Session은 복원, p2는 복원, p1은 여전히 trash
        let sessions = try await storage.fetchSessions()
        #expect(sessions.count == 1)

        let active = try await storage.fetchPhotos(sessionId: p1.sessionId)
        #expect(active.count == 1)
        #expect(active[0].id == p2.id)

        let trash = try await storage.fetchDeletedPhotos()
        #expect(trash.count == 1)
        #expect(trash[0].id == p1.id)
        #expect(trash[0].deletedAt == earlyStamp)
    }

    @Test("Plan E E1.b: restoreSession on 정상 상태 session → sessionNotFound")
    func restoreSessionNotInTrashThrows() async throws {
        let (storage, _, _) = try await makeStorageReal()
        let photo = try await storage.saveCapture(makePayload())

        await #expect(throws: MediaStorage.Error.sessionNotFound) {
            try await storage.restoreSession(sessionId: photo.sessionId)
        }
    }

    // MARK: - Trash background purge (Plan E Batch E5)

    @Test("Plan E E5: purgeExpired on empty trash → (0, 0)")
    func purgeExpiredEmpty() async throws {
        let (storage, _, _) = try await makeStorageReal()
        let result = try await storage.purgeExpired(cutoff: Date(timeIntervalSince1970: 1_000_000))
        #expect(result == PurgeExpiredResult(photosPurged: 0, sessionsPurged: 0))
    }

    @Test("Plan E E5: deletedAt < cutoff인 사진은 DB + file/thumb unlink, deletedAt >= cutoff는 보존")
    func purgeExpiredHonorsCutoff() async throws {
        let fakeFs = FakeFileOps()
        let (storage, db) = try await makeStorage(fs: fakeFs)
        let old = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_000)))
        let fresh = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_010)))
        try fakeFs.writeThumb(fileName: "\(old.id.uuidString).jpg", data: Data([0x01]))
        try fakeFs.writeThumb(fileName: "\(fresh.id.uuidString).jpg", data: Data([0x02]))

        try await storage.softDeletePhoto(id: old.id, at: Date(timeIntervalSince1970: 2_000))
        try await storage.softDeletePhoto(id: fresh.id, at: Date(timeIntervalSince1970: 8_000))

        let result = try await storage.purgeExpired(cutoff: Date(timeIntervalSince1970: 5_000))

        #expect(result.photosPurged == 1)
        #expect(result.sessionsPurged == 0)

        let surviving = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Photo") ?? 0
        }
        #expect(surviving == 1)
        #expect(try !fakeFs.finalExists(fileName: old.fileName))
        #expect(try fakeFs.finalExists(fileName: fresh.fileName))
        #expect(throws: FakeFileOpsError.self) {
            _ = try fakeFs.readThumb(fileName: "\(old.id.uuidString).jpg")
        }
        #expect(try fakeFs.readThumb(fileName: "\(fresh.id.uuidString).jpg") == Data([0x02]))
    }

    @Test("Plan E E5: 만료 세션 cascade — Session + 그 안 사진의 DB row + 파일 모두 제거")
    func purgeExpiredCascadesSession() async throws {
        let fakeFs = FakeFileOps()
        let (storage, db) = try await makeStorage(fs: fakeFs)
        let loc = LocationSnapshot(latitude: 0, longitude: 0, horizontalAccuracy: 10, placeName: nil)
        let p1 = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_000), location: loc))
        let p2 = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_010), location: loc))

        try await storage.softDeleteSession(sessionId: p1.sessionId, at: Date(timeIntervalSince1970: 2_000))

        let result = try await storage.purgeExpired(cutoff: Date(timeIntervalSince1970: 5_000))

        #expect(result.photosPurged == 2)
        #expect(result.sessionsPurged == 1)

        let counts = try await db.read { db -> (Int, Int) in
            let p = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Photo") ?? 0
            let s = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Session") ?? 0
            return (p, s)
        }
        #expect(counts.0 == 0)
        #expect(counts.1 == 0)
        #expect(try !fakeFs.finalExists(fileName: p1.fileName))
        #expect(try !fakeFs.finalExists(fileName: p2.fileName))
    }

    @Test("Plan E E5: cutoff 이전 trash + cutoff 이후 trash 혼합 — 부분 purge")
    func purgeExpiredMixed() async throws {
        let (storage, db, _) = try await makeStorageReal()
        let loc = LocationSnapshot(latitude: 0, longitude: 0, horizontalAccuracy: 10, placeName: nil)
        await storage.markPendingNewSession()
        _ = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_000), location: loc))
        await storage.markPendingNewSession()
        let s2Photo = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 2_000), location: loc))

        // s1: 오래된 trash → 만료 대상
        let p1Sessions = try await storage.fetchSessions()
        let oldSessionId = p1Sessions.last!.id  // s1 (oldest)
        try await storage.softDeleteSession(sessionId: oldSessionId, at: Date(timeIntervalSince1970: 1_500))
        // s2: 최근 trash → 보존
        try await storage.softDeleteSession(sessionId: s2Photo.sessionId, at: Date(timeIntervalSince1970: 9_000))

        let result = try await storage.purgeExpired(cutoff: Date(timeIntervalSince1970: 5_000))

        #expect(result.sessionsPurged == 1)
        #expect(result.photosPurged == 1)

        // s2 trash는 유지
        let trash = try await storage.fetchDeletedSessions()
        #expect(trash.count == 1)
        #expect(trash[0].id == s2Photo.sessionId)
        let remainingPhotoCount = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Photo") ?? 0
        }
        #expect(remainingPhotoCount == 1)
    }

    @Test("Plan E E5: active(미삭제) row는 cutoff와 무관하게 보존")
    func purgeExpiredIgnoresActiveRows() async throws {
        let (storage, db, _) = try await makeStorageReal()
        _ = try await storage.saveCapture(makePayload(at: Date(timeIntervalSince1970: 1_000)))

        let result = try await storage.purgeExpired(cutoff: Date(timeIntervalSince1970: 100_000_000))

        #expect(result == PurgeExpiredResult(photosPurged: 0, sessionsPurged: 0))
        let counts = try await db.read { db -> (Int, Int) in
            let p = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Photo") ?? 0
            let s = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Session") ?? 0
            return (p, s)
        }
        #expect(counts.0 == 1)
        #expect(counts.1 == 1)
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

/// GRDB trace closure에서 SELECT 호출 카운트 측정. lock-protected `_count`로
/// trace queue ↔ 테스트 측정 thread-safe.
private final class SelectCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    func increment() {
        lock.lock(); defer { lock.unlock() }
        _count += 1
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        _count = 0
    }

    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return _count
    }
}
