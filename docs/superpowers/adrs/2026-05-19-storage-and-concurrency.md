# ADR: Storage + Concurrency Boundary (v1 Core)

- **결정일:** 2026-05-19
- **상태:** 채택
- **위치:** Camork v1 Core Plan B Phase 1.0
- **참조:**
  - 마스터 설계서: `docs/superpowers/specs/2026-05-19-camork-rebuild-design.md`
  - Plan B 설계서 v3.3: `docs/superpowers/specs/2026-05-19-camork-v1-core-B-storage-camera-design.md`
  - Plan B 구현 계획 v1.4: `docs/superpowers/plans/2026-05-19-camork-v1-core-B-storage-camera.md`

---

## 컨텍스트

Camork v1 Core는 카메라 캡처 + 자동 세션 묶음 + 격리 저장 (정체성: **격리 > 빠른 공유 > 보안**). 메타데이터는 GRDB SQLite, 미디어는 파일 시스템에 저장 (마스터 spec §5, Plan A 결정 #1). 단일 actor `MediaStorage`가 모든 capture-save를 직렬화 (Plan A 결정 #3 단일 writer). 본 ADR은 Plan B의 모든 후속 Phase(1.1~4)가 의존하는 단일 권위 결정서.

---

## 결정 12항목

### 1. GRDB DatabaseWriter

- **채택:** `DatabaseQueue` (DatabasePool 아님).
- **근거:** v1 Core 데이터 규모(~수천 row 가정), 단일 actor writer 모델이라 동시 read 분기 의미 없음. DatabasePool은 multi-reader 시나리오에서만 가치.
- **GRDB 버전:** **v7.10.0** (2026-02-15 release, 공식 GitHub Releases 검증). `Package.resolved` exactVersion 고정.
- **빌드 실패 시:** 새 dependency 결정으로 기록 후 사용자 알림. silent downgrade 금지.

### 2. 단일 capture-save path

단일 `actor MediaStorage`가 모든 capture-save 흐름 소유. SessionManager actor는 만들지 않음.

**공개 API:**
- `saveCapture(_:) async throws -> Photo`
- `markPendingNewSession() async`
- `isPendingNewSession() async -> Bool`
- `updatePhotoNote(photoId:note:) async throws`
- `fetchPhoto(id:) async throws -> Photo?`
- `runReaper() async throws`
- `#if DEBUG` `injectSeededCapture(payload:)` (test-only, simulator 시각 검증용)

**공식 sequence (Step 0 snapshot + 5 step):**

0. `let manualFlag = pendingManualSessionStart` snapshot (await 전, actor isolation)
1. allocate photo id/path (UUID + relative fileName, 메모리 상)
2. write staging (`Media/.staging/<UUID>.heic`, **GRDB transaction 밖**)
3. atomic mv → `Media/<UUID>.heic`
4. GRDB transaction: previous photo fetch → `SessionAssignmentPolicy.decideSession(previous:, current:, manualFlag:)` → (newSession이면 Session insert + UUID 획득 / 아니면 기존 sessionId 사용) → Photo insert (sessionId 포함) → commit
5. **commit 성공 + captured manualFlag == true 인 경우에만** `pendingManualSessionStart = false`. captured manualFlag가 false면 in-flight 중 새로 set된 flag를 wipe하지 않음.

**핵심**: 파일 IO는 GRDB transaction **밖**에서 수행 (DB-lock 영향 최소화). GRDB write closure는 `[manualFlag, policy, photoId, fileName]` capture만, `self` 미참조 (Plan B v1.1 C6).

### 3. Failure matrix (4 buckets)

| 실패 시점 | 잔존물 | Cleanup 주체 |
|---|---|---|
| staging write fail (Step 2) | 없음 또는 부분 staging file | 즉시 staging cleanup |
| mv fail (Step 3) | `Media/.staging/<UUID>.heic` | 즉시 staging cleanup + abort |
| GRDB transaction fail (Step 4 — row insert / commit 포함) | `Media/<UUID>.heic` final orphan | best-effort 즉시 final 삭제 → 실패 시 **Orphan reaper** |
| crash after mv before commit | `Media/<UUID>.heic` final orphan | **Orphan reaper** (다음 앱 시작 시) |

- `removeStaging` / `removeFinal`은 best-effort (`try? fs.removeXxx`).
- **Orphan reaper** (`MediaStorage.runReaper()`): 앱 시작 시 호출. `Media/` enumerate → DB에 Photo row 없는 파일 삭제. Thumbnail 캐시도 동일.

### 4. SessionAssignmentPolicy: pure struct

- `struct SessionAssignmentPolicy: Sendable` — actor / DB / instance state 의존 없음.
- `decideSession(previous: Photo?, current: PhotoCapturePayload, manualFlag: Bool) -> Decision`
- `enum Decision: Equatable, Sendable { case newSession; case continueSession(sessionId: UUID) }`
- pseudocode body는 actor state(`pendingManualSessionStart`) 직접 접근 X. signature의 `manualFlag` 인자만 사용.
- 단위 테스트 직진 (6 edge case + GPS accuracy 25/30/35m 경계 + 시간 29/30/31min 경계 + `horizontalAccuracy nil` case).

### 5. @MainActor 적용 범위

- **적용**: SwiftUI View / ViewModel / UI state / `DependencyContainer` / `ObservableObject`.
- **비적용**: domain model struct (Photo / Session / LocationSnapshot / PhotoCapturePayload — 모두 `Sendable`) / repository protocol (`FileOps`) / `SessionAssignmentPolicy`.

### 6. AVFoundation callback → MediaStorage hop

callback queue (`AVCaptureSession`의 dedicated `DispatchQueue`, nonisolated)에서:

1. `LocationService.latestKnown()` **sync snapshot** 접근 (snapshot getter는 sync, non-Sendable 객체 미반환).
2. `PhotoCapturePayload` (Sendable struct) 조립 — `Data` + capturedAt + location snapshot + exif.
3. `onPayloadReady: @Sendable (Result<PhotoCapturePayload, Error>) -> Void` callback으로 CameraScreen에 전달.

CameraScreen은 `Task { @MainActor in await handleCaptureResult(result) }` 안에서:
- `defer { isInFlight = false }` — capture 성공/실패 모두 무조건 clear
- `do { let payload = try result.get(); _ = try await mediaStorage.saveCapture(payload) } catch { captureError = error }`

`AVCapturePhoto` 같은 non-Sendable 객체는 actor로 hop 금지. `Data` + metadata만 Sendable payload로.

### 7. Cross-actor 통신

- `await` 직접 호출만.
- `Combine` / `AsyncStream`은 UI 구독 (View ↔ actor)에만 사용.

### 8. Reentrancy

- `await` suspension point 전후로 상태 mutation 나누지 않는 구조 우선.
- 필요 시 GRDB transaction / idempotency key / 상태 snapshot으로 해결.
- **Lock은 최후 수단.**
- 단일 writer actor + GRDB transaction → 자연스럽게 reentrancy 위험 최소화.

### 9. 의존성 주입

- **Singleton 금지**.
- App root에서 `DependencyContainer` 1회 생성 → SwiftUI `Environment` 또는 `EnvironmentObject`로 전파.
- `try!` 금지 — `Bootstrap` enum (`pending` / `ready` / `failed`)으로 DB/file bootstrap 실패 시 `StorageInitErrorView` retry.
- 테스트: 격리된 actor 인스턴스를 `init` parameter로 주입 (in-memory DB + temp dir).

### 10. 테스트 전략

- in-memory `DatabaseQueue(configuration: CamorkDatabase.makeConfiguration())` — production과 동일 config (FK PRAGMA 등).
- `Migrations.makeMigrator().migrate(db)` 사용. test는 `DatabaseMigrator.appliedMigrations(_:) -> [String]` 으로 검증 (등록 순서 보존).
- `MediaFileSystem`은 temp directory로 격리. `FileOps` protocol을 통해 `FakeFileOps` 주입 가능 (staging write/mv/final-delete 실패 강제).
- `MediaStorageTestHooks` (`#if DEBUG`): **ordering gates 전용** (`afterManualFlagSnapshot`, `beforeDBCommit`). 파일 실패 주입은 `FakeFileOps`로 위임.
- `SessionAssignmentPolicy`는 actor 의존 없는 pure 테스트.

### 11. ExifData 필드

- `iso: Int?` / `shutterSpeed: Double?` / `aperture: Double?` / `focalLength: Double?` / `deviceModel: String?` / `osVersion: String?`
- 모두 옵셔널. EXIF 추출 실패 시 nil.
- JSON blob 직렬화 (Photo.exifJson). v1.1+ 검색에서 EXIF 조건은 비현실적 → 인덱스 불필요.

### 12. isExcludedFromBackup + Data Protection

**v1 Core 정책**: metadata DB + media 파일 + thumbnail 모두:
- `isExcludedFromBackup = true` (iCloud device backup / iTunes/Finder backup 모두 제외)
- Data Protection `FileProtectionType.completeUntilFirstUserAuthentication` (부팅 후 첫 잠금 해제까지 디스크 암호화 유지)

**적용 순서 (DB)**:
1. `metaDir` 디렉토리에 backup exclusion + Data Protection 적용 (파일 생성 전)
2. `DatabaseQueue` open + `Migrations.makeMigrator().migrate(queue)`
3. `camork.sqlite` + `camork.sqlite-wal` + `camork.sqlite-shm` 사이드카 각각에 적용 (`FileManager.fileExists` 확인 후)

**적용 순서 (Media)**:
1. `Media/` + `Media/.staging/` + `Thumbnails/` 디렉토리에 attribute 적용 (`MediaFileSystem.init throws`)
2. `writeStaging`은 `[.atomic, .completeFileProtectionUntilFirstUserAuthentication]` 옵션

**Trade-off**: 기기 분실/복원 시 데이터 손실 — Camork 데이터는 어떤 backup에도 들어가지 않음. 사용자에게 onboarding/설정에서 명시 (Plan E).

**v2 Trust 단계**: 사용자 옵션으로 iCloud Drive 백업 분리 (마스터 spec §3 v2 영역).

---

## 후속

본 ADR이 Plan B Phase 1.1 ~ Phase 4의 모든 결정 기반. Plan B 진행 중 본 ADR과 충돌하는 결정 발생 시 다음 중 하나:

1. **Plan source에 v1.5+ errata로 정정** (작은 충돌, ADR 범위 내).
2. **ADR 자체를 v2로 개정** + 모든 의존 phase 재검토 (큰 충돌, 예: GRDB 채택 자체 변경).

Swift strict concurrency 등 컴파일러 이슈로 인한 capture form / hop 형식 미세 조정은 (1) 범위 — plan 정정 없이 구현 단계에서 처리 (사용자 v1.4 review 메모).
