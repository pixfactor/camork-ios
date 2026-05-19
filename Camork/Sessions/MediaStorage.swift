import Foundation
import GRDB

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
                let previous = try fetchLatestPhoto(db: db)
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

private func fetchLatestPhoto(db: Database) throws -> Photo? {
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
