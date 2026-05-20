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
    enum Error: Swift.Error, Sendable, Equatable {
        case invalidFileName
        case sessionNotFound
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
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    let dateStr = formatter.string(from: date)
    if let placeName, !placeName.isEmpty {
        return "\(placeName) · \(dateStr)"
    }
    return dateStr
}
