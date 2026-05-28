import Foundation
import GRDB

/// 갤러리에서 세션 목록 정렬 옵션 (Plan C Phase 1.1). v1 Core는 createdAt 역방향만.
enum SessionSort: Sendable, Equatable {
    case createdAtDesc
}

/// 세션 카드의 4-photo preview + +N 배지 표시용 (Plan C Phase 1.2).
/// `previewPhotos`는 capturedAt 내림차순으로 최대 4개. `totalPhotoCount`는 deletedAt
/// 제외 전체 카운트 — +N 배지가 (total - previewPhotos.count)를 표시.
struct SessionPreview: Sendable {
    let sessionId: UUID
    let totalPhotoCount: Int
    let previewPhotos: [Photo]
}

/// 갤러리 첫 화면용 — 세션 + preview를 한 번에 fetch한 결과 (Plan C Phase 1.2).
/// 본 struct는 per-session N+1을 회피하기 위한 결과 packaging — 호출자는 list
/// 형태로 받아 갤러리 카드를 렌더링.
struct SessionWithPreview: Sendable {
    let session: Session
    let preview: SessionPreview
}

/// Plan E Batch E5 — `purgeExpired` 호출 결과. 진단/로그용 카운트. UI 분기는 사용하지
/// 않음 (cleanup은 비가시 background 작업).
struct PurgeExpiredResult: Sendable, Equatable {
    let photosPurged: Int
    let sessionsPurged: Int
}

/// 단일 capture-save writer (ADR #2). 모든 capture-save 흐름이 본 actor를 통해 직렬화된다.
///
/// ## saveCapture 5-step sequence (ADR #2 + v1.2 C6)
///
/// 0. `let manualFlag = pendingManualSessionStart` snapshot — actor isolation, await 전.
/// 1. allocate `photoId` (UUID) + relative `fileName` (메모리 상).
/// 2. staging write (`Media/.staging/<UUID>.heic`) — GRDB transaction 밖.
/// 3. atomic mv → `Media/<UUID>.heic`.
/// 4. GRDB transaction (closure self 미참조 / `[manualFlag, policy, photoId, fileName, payload]`
///    capture만): `fetchLatestPhoto` → `SessionAssignmentPolicy.decideSession` →
///    `resolveSessionId` → `insertPhoto` → commit.
/// 5. commit 성공 + **captured manualFlag == true** 인 경우에만 `pendingManualSessionStart = false`.
///    captured manualFlag가 false면 in-flight 도중 새로 set된 flag를 wipe하지 않음.
///
/// ## Failure matrix (ADR #3, 4 buckets)
///
/// | Step | 잔존물 | Cleanup |
/// |------|--------|---------|
/// | 2 staging write fail | 없음 또는 부분 staging file | 즉시 `removeStaging` |
/// | 3 mv fail | `Media/.staging/<UUID>.heic` | 즉시 `removeStaging` + abort |
/// | 4 GRDB transaction fail | `Media/<UUID>.heic` orphan | best-effort `removeFinal` → 실패 시 reaper |
/// | crash after mv before commit | `Media/<UUID>.heic` orphan | reaper (다음 앱 시작) |
actor MediaStorage {
    /// MediaStorage 도메인 에러.
    /// - `invalidFileName`: loadPhotoData가 canonical fileName invariant를 어긴 Photo를 거부.
    /// - `sessionNotFound`: updateSession* 의 UPDATE가 0 rows affected — sessionId가
    ///   존재하지 않거나 이미 deleted (deletedAt IS NULL 필터가 제외). Plan C Phase 1.3.
    /// - `photoNotFound`: Plan E Batch E1 trash 조작 시 photoId가 DB에 없거나 이미 trash
    ///   상태와 일치하지 않을 때. soft-delete/restore/purge 가드.
    enum Error: Swift.Error, Sendable, Equatable {
        case invalidFileName
        case sessionNotFound
        case photoNotFound
    }

    private var pendingManualSessionStart: Bool = false
    private let db: any DatabaseWriter
    private let fs: any FileOps
    private let policy: SessionAssignmentPolicy
    private let thumbnailCoordinator: ThumbnailCoordinator

    #if DEBUG
    private var testHooks: MediaStorageTestHooks = .init()
    #endif

    init(
        db: any DatabaseWriter,
        fs: any FileOps,
        policy: SessionAssignmentPolicy = .init(),
        thumbnailCoordinator: ThumbnailCoordinator = ThumbnailCoordinator()
    ) {
        self.db = db
        self.fs = fs
        self.policy = policy
        self.thumbnailCoordinator = thumbnailCoordinator
    }

    // MARK: - Public API (ADR #2)

    func markPendingNewSession() {
        pendingManualSessionStart = true
    }

    func isPendingNewSession() -> Bool {
        pendingManualSessionStart
    }

    func saveCapture(_ payload: PhotoCapturePayload) async throws -> Photo {
        // Step 0: snapshot manualFlag — actor isolation, await 전
        let manualFlag = pendingManualSessionStart

        #if DEBUG
        if let hook = testHooks.afterManualFlagSnapshot { try await hook() }
        #endif

        // Step 1: allocate id/path (메모리만)
        let photoId = UUID()
        let fileName = "\(photoId.uuidString).heic"

        // Step 2: staging write (GRDB transaction 밖)
        do {
            try fs.writeStaging(fileName: fileName, data: payload.data)
        } catch {
            try? fs.removeStaging(fileName: fileName)
            throw error
        }

        // Step 3: atomic mv → final
        do {
            try fs.moveStagingToFinal(fileName: fileName)
        } catch {
            try? fs.removeStaging(fileName: fileName)
            throw error
        }

        // Step 4: GRDB transaction — C6: closure는 self 캡쳐 X, snapshot + free function
        let policy = self.policy
        let photo: Photo
        do {
            #if DEBUG
            if let hook = testHooks.beforeDBCommit { try await hook() }
            #endif

            photo = try await db.write { [manualFlag, policy, photoId, fileName, payload] db in
                let previous = try queryLatestPhoto(db: db)
                let decision = policy.decideSession(
                    previous: previous,
                    current: payload,
                    manualFlag: manualFlag
                )
                let sessionId = try resolveSessionId(decision: decision, payload: payload, db: db)
                return try insertPhoto(
                    id: photoId,
                    fileName: fileName,
                    payload: payload,
                    sessionId: sessionId,
                    db: db
                )
            }
        } catch {
            try? fs.removeFinal(fileName: fileName)
            throw error
        }

        // Step 5: consumed flag wipe — captured manualFlag == true 인 경우에만
        if manualFlag {
            pendingManualSessionStart = false
        }
        return photo
    }

    /// `Media/`에 있지만 Photo row가 없는 파일을 정리. 앱 시작 시 호출.
    func runReaper() async throws {
        let existing: (fileNames: Set<String>, thumbNames: Set<String>) = try await db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, fileName FROM Photo")
            let fileNames = Set(rows.map { row in row["fileName"] as String })
            let thumbNames = Set(rows.map { row in "\(row["id"] as String).jpg" })
            return (fileNames, thumbNames)
        }
        let onDisk = try fs.enumerateFinal()
        for fileName in onDisk where !existing.fileNames.contains(fileName) {
            try? fs.removeFinal(fileName: fileName)
        }
        let thumbs = try fs.enumerateThumb()
        for fileName in thumbs where !existing.thumbNames.contains(fileName) {
            try? fs.removeThumb(fileName: fileName)
        }
    }

    /// Plan C Phase 1.4: `deletedAt IS NULL` 강제. soft-delete된 photo는 nil 반환 —
    /// caller(예: PhotoMemoEditor)에게 deletedAt 검사 책임을 분산하지 않음. Plan E
    /// Trash viewer가 deleted item을 노출해야 할 때 별도 API
    /// (예: `fetchPhotoIncludingDeleted(id:)`) 도입.
    func fetchPhoto(id: UUID) async throws -> Photo? {
        try await db.read { db in
            try Photo
                .filter(Column("id") == id.uuidString)
                .filter(Column("deletedAt") == nil)
                .fetchOne(db)
        }
    }

    /// 가장 최근 capturedAt + 미삭제 Photo (Phase 3.2 PhotoDetailView 진입점). Photo가
    /// 하나도 없으면 nil.
    func fetchLatestPhoto() async throws -> Photo? {
        try await db.read { db in
            try queryLatestPhoto(db: db)
        }
    }

    /// 갤러리 진입용 세션 목록 (Plan C Phase 1.1). deletedAt IS NULL 필터.
    /// 정렬은 `sortedBy` 매개변수로 결정 — v1 Core는 createdAt 역방향만 (`SessionSort`
    /// case 추가 시 본 switch도 확장).
    func fetchSessions(sortedBy: SessionSort = .createdAtDesc) async throws -> [Session] {
        try await db.read { db in
            let ordering: SQLOrdering = {
                switch sortedBy {
                case .createdAtDesc: return Column("createdAt").desc
                }
            }()
            return try Session
                .filter(Column("deletedAt") == nil)
                .order(ordering)
                .fetchAll(db)
        }
    }

    /// 세션 내 photo 전체 (Plan C Phase 1.1). capturedAt 오름차순 + deletedAt IS NULL.
    func fetchPhotos(sessionId: UUID) async throws -> [Photo] {
        try await db.read { db in
            try Photo
                .filter(Column("sessionId") == sessionId.uuidString)
                .filter(Column("deletedAt") == nil)
                .order(Column("capturedAt").asc)
                .fetchAll(db)
        }
    }

    /// 단일 세션의 4-photo preview + totalCount (Plan C Phase 1.2). UI는
    /// `fetchSessionsWithPreview`를 우선 사용 (per-session N+1 회피). 본 API는 단일 세션
    /// 디테일 진입처럼 한 세션만 필요한 경우.
    func fetchSessionPreview(sessionId: UUID) async throws -> SessionPreview {
        try await db.read { db in
            let total = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM Photo WHERE sessionId = ? AND deletedAt IS NULL",
                arguments: [sessionId.uuidString]
            ) ?? 0
            let previews = try Photo
                .filter(Column("sessionId") == sessionId.uuidString)
                .filter(Column("deletedAt") == nil)
                .order(Column("capturedAt").desc)
                .limit(4)
                .fetchAll(db)
            return SessionPreview(
                sessionId: sessionId,
                totalPhotoCount: total,
                previewPhotos: previews
            )
        }
    }

    /// 갤러리 첫 화면용 — 모든 세션 + 각 세션의 preview를 **per-session N+1 없이**
    /// 한 번에 fetch (Plan C Phase 1.2). 구현은 2 batched SQL:
    /// 1. 세션 목록 (sortedBy 적용, deletedAt IS NULL).
    /// 2. 모든 세션의 photo를 window function (ROW_NUMBER + COUNT)으로 한 번에 가져와
    ///    rn ≤ 4만 남김. 세션 수에 비례한 SQL 호출 없음.
    func fetchSessionsWithPreview(
        sortedBy: SessionSort = .createdAtDesc
    ) async throws -> [SessionWithPreview] {
        try await db.read { db in
            let ordering: SQLOrdering = {
                switch sortedBy {
                case .createdAtDesc: return Column("createdAt").desc
                }
            }()
            let sessions = try Session
                .filter(Column("deletedAt") == nil)
                .order(ordering)
                .fetchAll(db)
            guard !sessions.isEmpty else { return [] }

            let sessionIds = sessions.map { $0.id.uuidString }
            let placeholders = sessionIds.map { _ in "?" }.joined(separator: ",")
            let sql = """
                SELECT Photo.*, ranked.totalCount FROM (
                    SELECT
                        Photo.*,
                        ROW_NUMBER() OVER (PARTITION BY sessionId ORDER BY capturedAt DESC) AS rn,
                        COUNT(*) OVER (PARTITION BY sessionId) AS totalCount
                    FROM Photo
                    WHERE deletedAt IS NULL AND sessionId IN (\(placeholders))
                ) AS ranked
                JOIN Photo ON Photo.id = ranked.id
                WHERE ranked.rn <= 4
                ORDER BY ranked.sessionId, ranked.capturedAt DESC
                """
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(sessionIds))

            var photosBySession: [UUID: [Photo]] = [:]
            var totalBySession: [UUID: Int] = [:]
            for row in rows {
                let photo = try Photo(row: row)
                photosBySession[photo.sessionId, default: []].append(photo)
                if totalBySession[photo.sessionId] == nil {
                    totalBySession[photo.sessionId] = row["totalCount"] ?? 0
                }
            }

            return sessions.map { session in
                let previews = photosBySession[session.id] ?? []
                let total = totalBySession[session.id] ?? 0
                return SessionWithPreview(
                    session: session,
                    preview: SessionPreview(
                        sessionId: session.id,
                        totalPhotoCount: total,
                        previewPhotos: previews
                    )
                )
            }
        }
    }

    func fetchExportRows() async throws -> CamorkExportRows {
        try await db.read { db in
            let sessions = try Session
                .order(Column("createdAt").desc)
                .fetchAll(db)
            let photos = try Photo
                .order(Column("capturedAt").asc)
                .fetchAll(db)
            return CamorkExportRows(sessions: sessions, photos: photos)
        }
    }

    func upsertCloudSession(_ session: Session) async throws {
        try await db.write { db in
            try session.save(db)
        }
    }

    func upsertCloudPhotoMetadata(_ photo: Photo) async throws {
        _ = try canonicalMediaFileName(for: photo)
        try await db.write { db in
            try photo.save(db)
        }
    }

    /// CloudKit restore용 원본 파일 복원. 이미 로컬 원본이 있으면 덮어쓰지 않는다.
    /// metadata upsert와 파일 복원 순서는 caller가 정한다.
    @discardableResult
    func restoreCloudPhotoData(id: UUID, data: Data) throws -> Bool {
        let fileName = "\(id.uuidString).heic"
        guard try !fs.finalExists(fileName: fileName) else { return false }

        do {
            try fs.writeStaging(fileName: fileName, data: data)
            try fs.moveStagingToFinal(fileName: fileName)
            return true
        } catch {
            try? fs.removeStaging(fileName: fileName)
            throw error
        }
    }

    /// Photo의 raw 이미지 Data를 메모리로 로드 (Phase 3.2 PhotoDetailView 진입점).
    ///
    /// **Canonical fileName invariant**: `photo.fileName == "\(photo.id.uuidString).heic"`
    /// 가 깨진 Photo (DB corruption / 외부 도구 수정 / 잠재적 path traversal)는
    /// `Error.invalidFileName`으로 즉시 reject — fs.readFinal에 도달하기 전에
    /// 보안 boundary 차단.
    ///
    /// API가 String fileName 대신 Photo를 받는 이유: 호출자(현재는 CameraScreen)는
    /// 항상 DB에서 fetch한 Photo를 가지고 있고, raw fileName을 actor 경계 너머로
    /// 전달하는 것은 invariant 우회 위험. 외부 caller가 임의 fileName으로 actor를
    /// 사용할 수 없도록 표면 좁힘.
    ///
    /// 파일이 없으면 fs.readFinal이 throw — silent empty Data 반환 금지.
    func loadPhotoData(for photo: Photo) throws -> Data {
        let name = try canonicalMediaFileName(for: photo)
        return try fs.readFinal(fileName: name)
    }

    /// Photo thumbnail JPEG Data를 로드. cache hit은 즉시 반환하고, miss는 canonical
    /// original(`Media/<UUID>.heic`)에서 생성 후 `Library/Caches/.../Thumbnails`에 저장.
    ///
    /// `thumbnailFileName` 컬럼은 v1 Core에서 사용하지 않는다. thumbnail cache key는
    /// 항상 `photo.id.uuidString + ".jpg"`로 고정해 Photo row corruption이 cache path를
    /// 바꾸지 못하게 한다.
    func loadThumbnailData(for photo: Photo) async throws -> Data {
        let originalName = try canonicalMediaFileName(for: photo)
        let thumbName = "\(photo.id.uuidString).jpg"
        return try await thumbnailCoordinator.loadThumbnailData(
            id: photo.id,
            readCached: { [fs] in
                try fs.readThumb(fileName: thumbName)
            },
            generateAndCache: { [fs, thumbnailCoordinator] in
                let original = try fs.readFinal(fileName: originalName)
                let thumbnail = try await thumbnailCoordinator.generate(
                    original,
                    thumbnailCoordinator.shortSidePixels
                )
                try fs.writeThumb(fileName: thumbName, data: thumbnail)
                return thumbnail
            }
        )
    }

    func updatePhotoNote(photoId: UUID, note: String?) async throws {
        try await db.write { db in
            try db.execute(
                sql: "UPDATE Photo SET note = ? WHERE id = ?",
                arguments: [note, photoId.uuidString]
            )
        }
    }

    /// 세션명 변경 (Plan C Phase 1.3). UPDATE는 `deletedAt IS NULL` 필터 적용 — deleted
    /// 세션도 changesCount == 0 으로 결과되어 `Error.sessionNotFound` throw. SessionNameEditor가
    /// 빈/whitespace-only 이름을 차단한 뒤 trimmed name으로 호출 (도메인 invariant 분리).
    func updateSessionName(sessionId: UUID, name: String) async throws {
        try await db.write { db in
            try db.execute(
                sql: "UPDATE Session SET name = ? WHERE id = ? AND deletedAt IS NULL",
                arguments: [name, sessionId.uuidString]
            )
            if db.changesCount == 0 {
                throw Error.sessionNotFound
            }
        }
    }

    /// 세션 메모 변경 (Plan C Phase 1.3). nil → SQL NULL (clear). 빈 문자열은 그대로 저장
    /// (SessionNoteEditor 가 trim 없이 그대로 전달). UPDATE의 `deletedAt IS NULL` 필터로
    /// deleted session은 `Error.sessionNotFound`.
    func updateSessionNote(sessionId: UUID, note: String?) async throws {
        try await db.write { db in
            try db.execute(
                sql: "UPDATE Session SET note = ? WHERE id = ? AND deletedAt IS NULL",
                arguments: [note, sessionId.uuidString]
            )
            if db.changesCount == 0 {
                throw Error.sessionNotFound
            }
        }
    }

    /// 세션 이름 + 메모를 단일 GRDB transaction으로 commit. 두 UPDATE 사이에 부분 실패가
    /// 끼어들 수 없으므로 호출자가 "이름은 갱신 / 메모는 미갱신" 같은 split state를
    /// 보지 못한다. `deletedAt IS NULL` 필터로 deleted session은 `Error.sessionNotFound`.
    ///
    /// 정책 분리(`updateSessionName` / `updateSessionNote`)는 단일 필드 수정용 API로 유지
    /// — 단순한 변경은 그쪽이 더 명료. 본 메서드는 "정보 편집" sheet처럼 두 값이 함께
    /// 움직이는 진입점이 단일 transaction을 필요로 할 때 사용.
    func updateSessionInfo(sessionId: UUID, name: String, note: String?) async throws {
        try await db.write { db in
            try db.execute(
                sql: "UPDATE Session SET name = ?, note = ? WHERE id = ? AND deletedAt IS NULL",
                arguments: [name, note, sessionId.uuidString]
            )
            if db.changesCount == 0 {
                throw Error.sessionNotFound
            }
        }
    }

    // MARK: - Trash (Plan E Batch E1.a — photo-level)

    /// 휴지통에 들어 있는 모든 사진 (deletedAt IS NOT NULL). 최근 삭제 순으로 정렬.
    /// 30일 자동 영구삭제 후보를 식별하기 위한 query는 별도 cutoff variant로 도입할 예정.
    func fetchDeletedPhotos() async throws -> [Photo] {
        try await db.read { db in
            try Photo
                .filter(sql: "deletedAt IS NOT NULL")
                .order(Column("deletedAt").desc)
                .fetchAll(db)
        }
    }

    /// Photo를 휴지통으로 이동 (soft-delete). 이미 trash 상태인 row는 `deletedAt`을
    /// 새 시점으로 덮어쓰지 않고 `photoNotFound`로 alert — 동일 사진을 두 번 trash로
    /// 보내는 흐름은 호출자 책임으로 막아야 함. `at` 파라미터 default `Date()`이지만
    /// 테스트는 결정적 시점을 주입.
    func softDeletePhoto(id: UUID, at: Date = Date()) async throws {
        try await db.write { db in
            try db.execute(
                sql: "UPDATE Photo SET deletedAt = ? WHERE id = ? AND deletedAt IS NULL",
                arguments: [Int64(at.timeIntervalSince1970), id.uuidString]
            )
            if db.changesCount == 0 {
                throw Error.photoNotFound
            }
        }
    }

    /// 휴지통에서 복원. `deletedAt`을 nil로 되돌린다. 이미 정상 상태이면 photoNotFound.
    func restorePhoto(id: UUID) async throws {
        try await db.write { db in
            try db.execute(
                sql: "UPDATE Photo SET deletedAt = NULL WHERE id = ? AND deletedAt IS NOT NULL",
                arguments: [id.uuidString]
            )
            if db.changesCount == 0 {
                throw Error.photoNotFound
            }
        }
    }

    /// 휴지통 사진만 영구 삭제. DB row 제거 + final media + thumbnail cache 둘 다 best-effort unlink.
    /// ADR §3 4-bucket failure matrix 역방향 패턴: **DB 먼저 → 파일** 순. DB DELETE가 실패
    /// 하면 파일에 손대지 않고 throw. DB가 성공하면 파일 unlink 실패는 reaper가 후속
    /// orphan 청소를 통해 정리하므로 best-effort로 충분.
    func purgePhoto(id: UUID) async throws {
        try await db.write { db in
            try db.execute(
                sql: "DELETE FROM Photo WHERE id = ? AND deletedAt IS NOT NULL",
                arguments: [id.uuidString]
            )
            if db.changesCount == 0 {
                throw Error.photoNotFound
            }
        }
        let fileName = "\(id.uuidString).heic"
        let thumbName = "\(id.uuidString).jpg"
        try? fs.removeFinal(fileName: fileName)
        try? fs.removeThumb(fileName: thumbName)
    }

    // MARK: - Trash (Plan E Batch E1.b — session-level cascade)

    /// 휴지통에 들어 있는 모든 세션 (deletedAt IS NOT NULL). 최근 삭제 순.
    func fetchDeletedSessions() async throws -> [Session] {
        try await db.read { db in
            try Session
                .filter(sql: "deletedAt IS NOT NULL")
                .order(Column("deletedAt").desc)
                .fetchAll(db)
        }
    }

    /// 세션을 휴지통으로 이동. master spec §5.6에 따라 **세션 삭제 시 그 세션의 모든
    /// 사진도 같은 timestamp로 trash 처리**. 이미 개별 trash 상태였던 사진은 그대로
    /// (자신의 deletedAt 유지). 단일 transaction으로 일관성 유지.
    func softDeleteSession(sessionId: UUID, at: Date = Date()) async throws {
        try await db.write { db in
            let stamp = Int64(at.timeIntervalSince1970)
            try db.execute(
                sql: "UPDATE Session SET deletedAt = ? WHERE id = ? AND deletedAt IS NULL",
                arguments: [stamp, sessionId.uuidString]
            )
            if db.changesCount == 0 {
                throw Error.sessionNotFound
            }
            try db.execute(
                sql: "UPDATE Photo SET deletedAt = ? WHERE sessionId = ? AND deletedAt IS NULL",
                arguments: [stamp, sessionId.uuidString]
            )
        }
    }

    /// 휴지통에서 세션 복원. 세션 삭제 시 함께 trash로 간 사진들(같은 timestamp)만 복원.
    /// 사용자가 세션 삭제 *이전*에 개별 휴지통으로 보냈던 사진은 deletedAt timestamp가
    /// 다르므로 복원 대상에서 제외 — 사용자의 두 번의 의사 결정을 분리해 존중.
    func restoreSession(sessionId: UUID) async throws {
        try await db.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT deletedAt FROM Session WHERE id = ?",
                arguments: [sessionId.uuidString]
            ), let stamp: Int64 = row["deletedAt"] else {
                throw Error.sessionNotFound
            }
            try db.execute(
                sql: "UPDATE Session SET deletedAt = NULL WHERE id = ?",
                arguments: [sessionId.uuidString]
            )
            try db.execute(
                sql: "UPDATE Photo SET deletedAt = NULL WHERE sessionId = ? AND deletedAt = ?",
                arguments: [sessionId.uuidString, stamp]
            )
        }
    }

    // MARK: - Trash background purge (Plan E Batch E5 — 30일 보존 정책)

    /// `deletedAt < cutoff`인 사진/세션을 영구 삭제. master spec §5.6 "휴지통에서 30일 후
    /// 자동 영구 삭제". 호출자는 cutoff = now() - 30일을 전달. 결과 struct는 진단/로그용.
    ///
    /// 순서:
    /// 1. 만료 사진의 fileName 사전 enumerate (CASCADE로 사라지기 전에 캡쳐).
    /// 2. 단일 DB transaction: 만료 사진 DELETE + 만료 세션 DELETE (Photo.sessionId CASCADE).
    /// 3. 캡쳐한 fileName에 대해 best-effort file/thumb unlink. 실패는 reaper 후속 처리.
    func purgeExpired(cutoff: Date) async throws -> PurgeExpiredResult {
        let stamp = Int64(cutoff.timeIntervalSince1970)

        // Step 1: 만료 사진의 fileName 캡쳐 (개별 trash + 세션 cascade 양쪽 포함 —
        // softDeleteSession이 photo.deletedAt을 동일 stamp로 cascade했으므로 한 query로 OK).
        let expiredFileRefs: [(String, String)] = try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, fileName FROM Photo WHERE deletedAt IS NOT NULL AND deletedAt < ?",
                arguments: [stamp]
            )
            return rows.map { row in
                let id: String = row["id"]
                let fileName: String = row["fileName"]
                return (fileName, "\(id).jpg")
            }
        }

        // Step 2: DB DELETE photos + sessions in single transaction.
        let (photosPurged, sessionsPurged): (Int, Int) = try await db.write { db in
            try db.execute(
                sql: "DELETE FROM Photo WHERE deletedAt IS NOT NULL AND deletedAt < ?",
                arguments: [stamp]
            )
            let photoCount = db.changesCount
            try db.execute(
                sql: "DELETE FROM Session WHERE deletedAt IS NOT NULL AND deletedAt < ?",
                arguments: [stamp]
            )
            let sessionCount = db.changesCount
            return (photoCount, sessionCount)
        }

        // Step 3: best-effort file unlinks. Failures leave orphans for reaper.
        for (fileName, thumbName) in expiredFileRefs {
            try? fs.removeFinal(fileName: fileName)
            try? fs.removeThumb(fileName: thumbName)
        }

        return PurgeExpiredResult(
            photosPurged: photosPurged,
            sessionsPurged: sessionsPurged
        )
    }

    // MARK: - Test hooks (DEBUG only)

    #if DEBUG
    func installTestHook(
        afterManualFlagSnapshot: (@Sendable () async throws -> Void)? = nil,
        beforeDBCommit: (@Sendable () async throws -> Void)? = nil
    ) {
        if let h = afterManualFlagSnapshot { testHooks.afterManualFlagSnapshot = h }
        if let h = beforeDBCommit { testHooks.beforeDBCommit = h }
    }
    #endif
}

// MARK: - DB free functions (C6 — closure self 캡쳐 회피)

private func queryLatestPhoto(db: Database) throws -> Photo? {
    try Photo
        .order(Column("capturedAt").desc)
        .filter(Column("deletedAt") == nil)
        .fetchOne(db)
}

private func resolveSessionId(
    decision: SessionAssignmentPolicy.Decision,
    payload: PhotoCapturePayload,
    db: Database
) throws -> UUID {
    switch decision {
    case .continueSession(let id):
        return id
    case .newSession:
        let session = Session(
            id: UUID(),
            name: defaultSessionName(at: payload.capturedAt, placeName: payload.location?.placeName),
            createdAt: payload.capturedAt,
            firstLocation: payload.location
        )
        try session.insert(db)
        return session.id
    }
}

private func insertPhoto(
    id: UUID,
    fileName: String,
    payload: PhotoCapturePayload,
    sessionId: UUID,
    db: Database
) throws -> Photo {
    let photo = Photo(
        id: id,
        sessionId: sessionId,
        fileName: fileName,
        thumbnailFileName: nil,
        kind: .photo,
        capturedAt: payload.capturedAt,
        location: payload.location,
        exif: payload.exif
    )
    try photo.insert(db)
    return photo
}

private func canonicalMediaFileName(for photo: Photo) throws -> String {
    let name = photo.fileName
    // Defense-in-depth: equality check만으로도 path traversal/separator를 제거하지만
    // invariant를 명시적으로 표현한다.
    guard !name.contains("/"), !name.contains("..") else {
        throw MediaStorage.Error.invalidFileName
    }
    guard name == "\(photo.id.uuidString).heic" else {
        throw MediaStorage.Error.invalidFileName
    }
    return name
}

private func defaultSessionName(at date: Date, placeName: String?) -> String {
    SessionTitlePolicy.automaticName(at: date, placeName: placeName)
}
