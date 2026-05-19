import Foundation
import GRDB

/// 갤러리에서 세션 목록 정렬 옵션 (Plan C Phase 1.1). v1 Core는 createdAt 역방향만.
enum SessionSort: Sendable, Equatable {
    case createdAtDesc
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
    /// MediaStorage 도메인 에러. 현재는 loadPhotoData가 canonical fileName invariant를
    /// 어긴 Photo를 거부할 때 throw.
    enum Error: Swift.Error, Sendable, Equatable {
        case invalidFileName
    }

    private var pendingManualSessionStart: Bool = false
    private let db: any DatabaseWriter
    private let fs: any FileOps
    private let policy: SessionAssignmentPolicy

    #if DEBUG
    private var testHooks: MediaStorageTestHooks = .init()
    #endif

    init(
        db: any DatabaseWriter,
        fs: any FileOps,
        policy: SessionAssignmentPolicy = .init()
    ) {
        self.db = db
        self.fs = fs
        self.policy = policy
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
        let dbFileNames: Set<String> = try await db.read { db in
            let names = try String.fetchAll(db, sql: "SELECT fileName FROM Photo")
            return Set(names)
        }
        let onDisk = try fs.enumerateFinal()
        for fileName in onDisk where !dbFileNames.contains(fileName) {
            try? fs.removeFinal(fileName: fileName)
        }
    }

    func fetchPhoto(id: UUID) async throws -> Photo? {
        try await db.read { db in
            try Photo.fetchOne(db, key: id.uuidString)
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
        let name = photo.fileName
        // Defense-in-depth: equality check만으로도 path traversal/separator를 제거
        // 하지만 invariant를 명시적으로 표현.
        guard !name.contains("/"), !name.contains("..") else {
            throw Error.invalidFileName
        }
        guard name == "\(photo.id.uuidString).heic" else {
            throw Error.invalidFileName
        }
        return try fs.readFinal(fileName: name)
    }

    func updatePhotoNote(photoId: UUID, note: String?) async throws {
        try await db.write { db in
            try db.execute(
                sql: "UPDATE Photo SET note = ? WHERE id = ?",
                arguments: [note, photoId.uuidString]
            )
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
