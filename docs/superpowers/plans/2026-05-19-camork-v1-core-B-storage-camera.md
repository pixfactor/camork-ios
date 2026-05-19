# Camork v1 Core — Plan B: Storage + Camera Implementation Plan (v1.1)

> **For agentic workers:**
> **Default mode for Plan B: `superpowers:executing-plans` (Inline).** Plan A는 Inline으로 성공했고, 본 세션은 사용자 terminal review 중심으로 진행됨.
> `superpowers:subagent-driven-development`는 **사용자 명시 승인** 또는 **분명히 독립적인 slice** (예: GRDB 의존 없는 pure helper 단위 테스트만) 전용 옵션. 기본 흐름에서는 단일 세션 Inline 실행 + Lore commit + 사용자 확인 사이클.
> Steps use checkbox (`- [ ]`) syntax for tracking.

> **v1.1 개정 (2026-05-19):** ai-slop-cleaner workflow로 8 Critical + 1 Should-fix 정정 — GRDB 버전 (C1), 실행 모드 기본값 (C2), 중복 Sessions/ block (C3), Phase 2/3 task 확장 (C4), 결정적 race/failure 테스트 + FileOps protocol (C5), self closure 제거 (C6), GRDB DatabaseMigrator API (C7), Date <-> Int64 codec 명시 (C8), XcodeGen product 명시 (S1). 부록 §A에 매핑 표.

**Goal:** Spec v3.3의 v1 Core 핵심 루프(촬영 → 자동 세션 묶음 → 로컬 저장 → 직전 사진 확인 → 메모 편집)를 구현. Storage 인프라(GRDB + 단일 writer actor) + Camera(AVFoundation thin wrapper + UI) + PhotoDetail(메모 편집)을 닫는다.

**Architecture:** 단일 `actor MediaStorage`가 모든 capture-save를 직렬화 (GRDB transaction + Sendable payload hop). `struct SessionAssignmentPolicy`는 pure helper. AVFoundation은 thin wrapper, 비즈니스 로직은 `Camork/Camera/Internal/`로 분리. UI는 `@MainActor`, View body는 Preview 위임 (Plan A 정책 답습).

**Tech Stack:** Swift 5 (language mode), SwiftUI, AVFoundation, CoreLocation, **GRDB.swift** (SPM), Swift Testing, XcodeGen, iOS 17+ deployment / Xcode 26.

**선행 컨텍스트:**
- Spec v3.3: `docs/superpowers/specs/2026-05-19-camork-v1-core-B-storage-camera-design.md`
- Plan A 완료: `docs/superpowers/reports/2026-05-19-plan-A-setup-complete.md`
- 부모 가이드: `/Users/jedel/Projects/CLAUDE.md`
- 앱 가이드: `camork-ios/CLAUDE.md`

## Commit Policy

Plan A v3 Commit Policy 상속. **Lore Commit Protocol** (Codex 환경 기준):

```
<intent line — 왜>
<empty>
<context, constraints, approach>
<empty>
Constraint: ...
Rejected: ...
Confidence: high|medium|low
Scope-risk: narrow|moderate|broad
Directive: ...
Tested: ...
Not-tested: ...
```

다른 환경에서 실행 시 해당 환경의 commit 규칙 우선. 본 plan의 commit 예시는 Lore 기준.

## Destination 환경변수

모든 xcodebuild 명령은 `$CAMORK_SIM` 환경변수 사용:
```bash
export CAMORK_SIM="iPhone 17 Pro"   # 또는 가용한 다른 iPhone 모델
```

---

## SwiftUI 테스트 정책 (Plan A 상속)

1. 단위 테스트의 책임은 로직 검증이지 SwiftUI 렌더 검증이 아님.
2. View body 시각 검증은 Xcode Preview에 위임.
3. 분기/계산 코드는 internal/static func로 추출하고 단위 테스트.
4. View 자체에 toy 테스트는 두지 않음.
5. trait/asset 등 외부 의존은 명시 bundle로 단위 테스트 가능.

---

## File Structure (Plan B 신규/수정 대상)

```
Camork/
├─ Storage/                          [신규 — Plan B Phase 1]
│  ├─ Database.swift                 — GRDB DatabaseWriter open + path 정책
│  ├─ Migrations.swift               — migration v1 (Photo, Session) + makeMigrator() 노출
│  ├─ MediaFileSystem.swift          — staging/.staging/final/thumbnail (init throws, FileOps protocol 구현)
│  ├─ FileOps.swift                  — protocol (writeStaging / mv / removeFinal 등) for test seams
│  ├─ Photo.swift                    — struct + GRDB codec (Date ↔ Int64 explicit DatabaseValueConvertible)
│  ├─ Session.swift                  — struct + GRDB codec (동일)
│  ├─ LocationSnapshot.swift         — struct, embed columns
│  ├─ MediaKind.swift                — enum (photo only, CHECK 제약과 일치)
│  └─ ExifData.swift                 — struct, JSON blob 직렬화
├─ Sessions/                         [신규 — Phase 1.5, 1.6, 3.1]
│  ├─ PhotoCapturePayload.swift      — Sendable struct (callback → actor hop)
│  ├─ SessionAssignmentPolicy.swift  — pure helper, decideSession
│  ├─ MediaStorage.swift             — actor (단일 writer + saveCapture + Orphan reaper)
│  ├─ MediaStorageTestHooks.swift    [test-only seam, #if DEBUG] — afterManualFlagSnapshot / beforeDBCommit hooks for deterministic race tests
│  └─ PhotoMemoEditor.swift          — 메모 update 로직 (Phase 3.1, MediaStorage 위임)
├─ Services/                         [신규 — Phase 2a, 2b]
│  ├─ PermissionsService.swift       — 카메라/위치 권한 매핑 (마이크 제외)
│  └─ LocationService.swift          — CLLocationManager, latest known snapshot
├─ Camera/                           [신규 — Phase 2]
│  ├─ CameraSession.swift            — AVCaptureSession thin wrapper
│  ├─ MediaCapture.swift             — AVCapturePhotoCaptureDelegate, Sendable payload 변환
│  ├─ CameraView.swift               — UIViewControllerRepresentable (preview layer)
│  ├─ CameraScreen.swift             — 메인 카메라 화면 (@MainActor SwiftUI View)
│  └─ Internal/                      — 비즈니스 로직 (단위 테스트 대상)
│     ├─ CameraScreenViewState.swift — permission state → UI variant + chip pending + in-flight ignore
│     ├─ CameraSessionBuilder.swift  — AVCaptureSession configuration 빌더 (pure)
│     └─ ExifBuilder.swift           — AVCapturePhoto → ExifData
├─ Gallery/                          [신규 — Phase 3 (Plan C에서 확장)]
│  └─ PhotoDetailView.swift          — 단일 사진 풀스크린 + 메모 sheet
└─ AppShell/
   └─ DependencyContainer.swift      [신규 — Phase 2c] App root container (Environment)

CamorkTests/                         [신규 — 각 phase에서 누적]
├─ MigrationsTests.swift             — Phase 1.1
├─ MediaFileSystemTests.swift        — Phase 1.1
├─ SessionAssignmentPolicyTests.swift — Phase 1.3 (6 edge case + 경계)
├─ MediaStorageTests.swift           — Phase 1.4 (saveCapture + Failure matrix + Reaper + race-style)
├─ PermissionsServiceTests.swift     — Phase 2a
├─ CameraSessionBuilderTests.swift   — Phase 2a
├─ ExifBuilderTests.swift            — Phase 2b
├─ CameraScreenViewStateTests.swift  — Phase 2c (UI 분기 + chip in-flight ignore)
└─ PhotoMemoEditorTests.swift        — Phase 3
```

**원칙**: 각 파일 단일 책임. AVFoundation wrapper는 얇게 + 비즈니스 로직은 `Internal/`로 격리. 추후 SwiftPM 로컬 패키지로 분리 가능한 구조.

---

## Phase 1 — Storage 인프라 (UI 없이 단위 테스트로만 검증)

**완료 기준** (spec §1.4 Phase 1):
- `xcodebuild test` SUCCEEDED — 신규 단위 테스트 + Plan A 기존 7건 모두 통과
- 빌드 경고 0건
- 시뮬레이터 시각 변화 없음 (의도)

---

### Task 1.0 — Storage + 동시성 단일 ADR

**Files:**
- Create: `docs/superpowers/adrs/2026-05-19-storage-and-concurrency.md`

- [ ] **Step 1: 디렉토리 생성**

```bash
mkdir -p docs/superpowers/adrs
```

- [ ] **Step 2: ADR 작성**

문서 골격 — spec v3.3 §1.0 ADR의 12개 항목을 정식 문서로 풀어 작성:

```markdown
# ADR: Storage + Concurrency Boundary (v1 Core)

- 결정일: 2026-05-19
- 상태: 채택
- 컨텍스트: Plan B Phase 1.0 첫 task. 후속 Phase 모두 본 ADR을 참조.

## 1. GRDB DatabaseWriter 선택
- DatabaseQueue 채택. DatabasePool은 v1 Core 규모(~수천 row)엔 과함.
- GRDB 버전: 7.x 최신 stable (Plan B 구현 시 latest 확인 후 Package.resolved 고정).

## 2. 단일 capture-save path
- 단일 actor MediaStorage가 모든 capture-save 흐름 소유.
- 공개 API: saveCapture(_:), markPendingNewSession(), isPendingNewSession(),
  updatePhotoNote(...), fetchPhoto(id:), runReaper().
- 공식 sequence (Step 0~5, spec §1.0 ADR 참조).

## 3. Failure matrix 4 buckets + Cleanup 정책
(spec v3.3 §1.0 ADR 항목 #3 그대로)

## 4. SessionAssignmentPolicy: pure struct
- actor/DB/instance state 의존 없음.
- decideSession(previous: Photo?, current: PhotoCapturePayload, manualFlag: Bool) -> Decision

## 5. @MainActor 적용 범위
- View / ViewModel / UI state만.
- Photo/Session struct + Storage protocol은 nonisolated.

## 6. AVFoundation → MediaStorage hop 규칙
- callback queue에서 LocationService.latestKnown 동기 snapshot 접근.
- PhotoCapturePayload (Sendable) 조립 후 Task { [payload] in await mediaStorage.saveCapture(payload) }.

## 7. Cross-actor 통신
- await 직접 호출만. Combine/AsyncStream UI 구독에만.

## 8. Reentrancy
- await 전후 mutation 안 나누는 구조. Lock 최후 수단. saveCapture는 GRDB transaction + actor isolation으로 직렬화.

## 9. 의존성 주입
- Singleton 금지. App root DependencyContainer → Environment.

## 10. 테스트 전략
- in-memory DB + temp dir로 actor 격리.
- SessionAssignmentPolicy는 actor 의존 없는 pure 테스트.
- in-flight race-style 테스트: captured manualFlag == false 시 markPending 호출 시뮬 → commit 후 새 flag 유지 검증.

## 11. ExifData 필드
- iso / shutterSpeed / aperture / focalLength / deviceModel / osVersion — 모두 옵셔널.

## 12. isExcludedFromBackup 결정
- v1 Core: metadata DB + media 파일 모두 exclude.
- Trade-off: 기기 분실/복원 시 데이터 손실.
- v2 Trust 단계: 사용자 옵션으로 분리.
```

- [ ] **Step 3: 커밋** (Lore)

```bash
git add docs/superpowers/adrs/
git commit -F- <<'EOF'
add Storage + concurrency ADR for Plan B Phase 1.0

spec v3.3 §1.0 ADR의 12개 항목을 정식 문서로 풀어 작성. 후속 Phase는 본 ADR을 참조.

Constraint: GRDB DatabaseQueue, 단일 MediaStorage writer actor, pure SessionAssignmentPolicy, file IO GRDB transaction 밖, captured manualFlag snapshot + conditional clear, in-memory test 격리
Rejected: DatabasePool — v1 Core 규모 과함
Rejected: SessionManager actor 분리 — split-brain 위험
Rejected: SwiftData — actor 경계 + AVFoundation 백그라운드 큐 예측성 떨어짐
Confidence: high
Scope-risk: narrow
Directive: Phase 1.1부터 본 ADR을 따라 구현. 모든 후속 결정은 ADR 항목 N으로 인용.
Tested: 문서 작성 — 실제 검증은 후속 Phase에서
Not-tested: 본 ADR의 가설이 실제 Swift 6 strict concurrency와 호환 — v1.1 ADR 개정 시점에 검증
EOF
```

---

### Task 1.1 — GRDB SPM dependency 추가

**Files:**
- Modify: `project.yml` (packages section 추가)

- [ ] **Step 1: project.yml에 GRDB SPM 추가** (C1 + S1)

**버전 결정**: 공식 GitHub Releases 페이지에서 확인된 최신 stable은 **v7.10.0 (2026-02-15 release)**. exactVersion으로 pin. 만약 7.10.0 빌드 실패하면 **새 dependency 결정으로 기록** (silent downgrade 금지).

```yaml
packages:
  GRDB:
    url: https://github.com/groue/GRDB.swift.git   # 공식 .git suffix
    exactVersion: "7.10.0"

targets:
  Camork:
    # ... 기존 설정 ...
    dependencies:
      - package: GRDB
        product: GRDB   # XcodeGen이 product를 명시적으로 link
```

- [ ] **Step 2: xcodegen + 빌드 검증**

```bash
xcodegen generate && \
xcodebuild -scheme Camork \
  -destination "platform=iOS Simulator,name=$CAMORK_SIM" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
  build 2>&1 | tail -10
```

Expected: GRDB 의존성 다운로드 + `BUILD SUCCEEDED`.

- [ ] **Step 3: Package.resolved 확인 + 커밋**

```bash
ls Camork.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved 2>/dev/null || \
  find . -name "Package.resolved" -not -path "*/DerivedData/*"

git add project.yml Camork.xcodeproj/
# Package.resolved 위치에 따라 추가
git add Camork.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved 2>/dev/null || true

git commit -F- <<'EOF'
add GRDB.swift v7.10.0 SPM dependency pinned via exactVersion

Plan B Phase 1.1 — GRDB.swift v7.10.0 (2026-02-15 release, 공식 GitHub Releases
페이지 검증)을 exactVersion으로 pin. metadata DB 전용 (미디어는 파일 시스템).
product: GRDB 명시.

Constraint: exactVersion 고정 (ADR 결정 #1), 공식 .git URL + product 명시, GRDB는 metadata only
Rejected: "from:" 범위 의존성 — minor 변화로 빌드 깨질 가능성
Rejected: silent downgrade — 빌드 실패 시 새 dependency 결정으로 기록해야 함
Confidence: high
Scope-risk: narrow
Directive: 후속 task에서 GRDB import + DatabaseWriter 사용. 빌드 실패 시 immediate halt + 사용자 알림.
Tested: xcodebuild build SUCCEEDED, GRDB import 가능, Package.resolved에 7.10.0 고정 확인
Not-tested: 실제 GRDB API 동작 — Task 1.2 Database.swift 작성 시 검증
EOF
```

---

### Task 1.2 — Migrations + Database 골격 (C7 GRDB API 정정)

**Files:**
- Create: `Camork/Storage/Database.swift`
- Create: `Camork/Storage/Migrations.swift`
- Test: `CamorkTests/MigrationsTests.swift`

**C7 정정**: 마이그레이션 검증은 GRDB의 비공식 `schemaVersion()` 대신 **공식 `DatabaseMigrator.appliedMigrations(_:)` API** 사용. `Migrations.makeMigrator() -> DatabaseMigrator`를 노출해 test가 직접 호출.

- [ ] **Step 1: 실패 테스트** (Migration idempotent + schema 생성, C7 정정 API)

```swift
// CamorkTests/MigrationsTests.swift
import Testing
import GRDB
@testable import Camork

@Suite("Migrations")
struct MigrationsTests {
    @Test("migration v1 두 번 호출해도 appliedMigrations 동일")
    func idempotent() throws {
        let db = try DatabaseQueue()
        let migrator = Migrations.makeMigrator()

        try migrator.migrate(db)
        let first = try db.read { try migrator.appliedIdentifiers($0) }

        try migrator.migrate(db)
        let second = try db.read { try migrator.appliedIdentifiers($0) }

        #expect(first == second)
        #expect(first.contains("v1"))
    }

    @Test("v1 schema 생성 후 Session/Photo 테이블 존재")
    func schemaCreated() throws {
        let db = try DatabaseQueue()
        try Migrations.makeMigrator().migrate(db)

        try db.read { row in
            let sessions = try Row.fetchAll(row, sql: "SELECT name FROM sqlite_master WHERE type='table'")
                .compactMap { $0["name"] as String? }
            #expect(sessions.contains("Session"))
            #expect(sessions.contains("Photo"))
        }
    }

    @Test("Photo.kind에 'video' insert 시 CHECK 제약으로 실패")
    func checkConstraint() throws {
        let db = try DatabaseQueue()
        try Migrations.makeMigrator().migrate(db)

        #expect(throws: DatabaseError.self) {
            try db.write { row in
                try row.execute(sql: """
                    INSERT INTO Session(id, name, createdAt) VALUES('s1','test',0);
                    INSERT INTO Photo(id, sessionId, fileName, kind, capturedAt)
                    VALUES('p1','s1','x.heic','video',0);
                    """)
            }
        }
    }
}
```

- [ ] **Step 2: 실패 확인**

```bash
xcodegen generate && \
xcodebuild -scheme Camork \
  -destination "platform=iOS Simulator,name=$CAMORK_SIM" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
  test 2>&1 | tail -10
```

Expected: 컴파일 실패 (`Migrations`, `Database` 미정의).

- [ ] **Step 3: Database.swift + Migrations.swift 작성**

```swift
// Camork/Storage/Database.swift
import Foundation
import GRDB

enum CamorkDatabase {
    static func open() throws -> DatabaseQueue {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true
        )
        let metaDir = appSupport.appendingPathComponent("Camork/Metadata", isDirectory: true)
        try FileManager.default.createDirectory(at: metaDir, withIntermediateDirectories: true)

        var url = metaDir.appendingPathComponent("camork.sqlite")
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)

        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }

        let queue = try DatabaseQueue(path: url.path, configuration: config)
        try Migrations.makeMigrator().migrate(queue)
        return queue
    }
}
```

```swift
// Camork/Storage/Migrations.swift
import GRDB

enum Migrations {
    /// 공식 GRDB API 노출 — test가 `appliedIdentifiers(_:)`로 검증 가능 (C7)
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE Session (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    note TEXT,
                    createdAt INTEGER NOT NULL,
                    endedAt INTEGER,
                    firstLat REAL,
                    firstLon REAL,
                    firstHorizontalAccuracy REAL,
                    firstPlaceName TEXT,
                    deletedAt INTEGER
                );
                CREATE TABLE Photo (
                    id TEXT PRIMARY KEY,
                    sessionId TEXT NOT NULL REFERENCES Session(id) ON DELETE CASCADE,
                    fileName TEXT NOT NULL,
                    thumbnailFileName TEXT,
                    kind TEXT NOT NULL CHECK (kind IN ('photo')),
                    capturedAt INTEGER NOT NULL,
                    lat REAL,
                    lon REAL,
                    horizontalAccuracy REAL,
                    placeName TEXT,
                    exifJson TEXT,
                    note TEXT,
                    deletedAt INTEGER
                );
                CREATE INDEX idx_Photo_sessionId ON Photo(sessionId);
                CREATE INDEX idx_Photo_capturedAt ON Photo(capturedAt DESC);
                CREATE INDEX idx_Photo_deletedAt ON Photo(deletedAt);
                CREATE INDEX idx_Session_createdAt ON Session(createdAt DESC);
                """)
        }

        return migrator
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
xcodegen generate && \
xcodebuild -scheme Camork \
  -destination "platform=iOS Simulator,name=$CAMORK_SIM" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
  test 2>&1 | tail -15
```

Expected: 3개 신규 테스트 + Plan A 7건 = 10건 통과.

- [ ] **Step 5: 커밋**

```bash
git add Camork/Storage/Database.swift Camork/Storage/Migrations.swift \
    CamorkTests/MigrationsTests.swift Camork.xcodeproj/
git commit -F- <<'EOF'
add GRDB Database open and v1 migration with CHECK constraints

Plan B Phase 1.2 — DatabaseQueue를 Library/Application Support/Camork/Metadata/
에 생성, isExcludedFromBackup 적용 (ADR #12). v1 migration으로 Session/Photo +
4개 인덱스 생성. Photo.kind에 CHECK (kind IN ('photo'))로 v1 Core photo-only 강제.

Constraint: DatabaseQueue + WAL journal mode, isExcludedFromBackup = true, CHECK 제약으로 v1 Core photo only DB 차원 강제
Rejected: in-memory DB만 — 실 사용은 영속 필요
Rejected: kind CHECK 없이 Swift enum에만 의존 — DB write 시 잘못된 row 검출 불가
Confidence: high
Scope-risk: narrow
Directive: Phase 1.3/1.4에서 본 schema를 GRDB FetchableRecord/PersistableRecord로 매핑
Tested: 3건 단위 테스트 (idempotent migration, schema 생성, CHECK 제약 실패)
Not-tested: 실제 file path가 isExcludedFromBackup true인지 실기기 검증 — Phase 4 manual checklist
EOF
```

---

### Task 1.3 — 모델 (Photo, Session, LocationSnapshot, MediaKind, ExifData) + Date codec (C8)

**Files:**
- Create: `Camork/Storage/Photo.swift`
- Create: `Camork/Storage/Session.swift`
- Create: `Camork/Storage/LocationSnapshot.swift`
- Create: `Camork/Storage/MediaKind.swift`
- Create: `Camork/Storage/ExifData.swift`

**C8 정정**: schema의 `createdAt INTEGER NOT NULL`, `capturedAt INTEGER NOT NULL`, `deletedAt INTEGER`은 **Unix epoch seconds (Int64)**. GRDB가 silently `Date.timeIntervalSinceReferenceDate` 또는 ISO 8601 string으로 매핑하지 않도록, **`DatabaseValueConvertible` 명시 매핑**을 모델에 둠.

- [ ] **Step 1: 5개 파일 작성** (C8 Date codec explicit)

각 모델에 명시적 `DatabaseValueConvertible` 매핑:

```swift
// Camork/Storage/Photo.swift (예시)
import GRDB
import Foundation

struct Photo: Identifiable, Codable, Sendable, FetchableRecord, PersistableRecord {
    let id: UUID
    let sessionId: UUID
    let fileName: String
    let thumbnailFileName: String?
    let kind: MediaKind
    let capturedAt: Date
    let location: LocationSnapshot?
    let exif: ExifData?
    var note: String?
    var deletedAt: Date?

    // C8: Date ↔ Int64 (Unix epoch seconds) 명시 매핑
    enum Columns: String, ColumnExpression {
        case id, sessionId, fileName, thumbnailFileName, kind
        case capturedAt, lat, lon, horizontalAccuracy, placeName
        case exifJson, note, deletedAt
    }

    init(row: Row) throws {
        id = try UUID.fromDatabaseValue(row[Columns.id]) ?? UUID()
        sessionId = try UUID.fromDatabaseValue(row[Columns.sessionId]) ?? UUID()
        fileName = row[Columns.fileName]
        thumbnailFileName = row[Columns.thumbnailFileName]
        kind = MediaKind(rawValue: row[Columns.kind]) ?? .photo
        capturedAt = Date(timeIntervalSince1970: row[Columns.capturedAt])   // C8: Int64 → Date
        // LocationSnapshot embed
        if let lat: Double = row[Columns.lat], let lon: Double = row[Columns.lon] {
            location = LocationSnapshot(
                latitude: lat, longitude: lon,
                horizontalAccuracy: row[Columns.horizontalAccuracy] ?? -1,
                placeName: row[Columns.placeName]
            )
        } else { location = nil }
        if let json: String = row[Columns.exifJson] {
            exif = try JSONDecoder().decode(ExifData.self, from: Data(json.utf8))
        } else { exif = nil }
        note = row[Columns.note]
        if let d: TimeInterval = row[Columns.deletedAt] {
            deletedAt = Date(timeIntervalSince1970: d)
        } else { deletedAt = nil }
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id.uuidString
        container[Columns.sessionId] = sessionId.uuidString
        container[Columns.fileName] = fileName
        container[Columns.thumbnailFileName] = thumbnailFileName
        container[Columns.kind] = kind.rawValue
        container[Columns.capturedAt] = capturedAt.timeIntervalSince1970   // C8: Date → Int64
        container[Columns.lat] = location?.latitude
        container[Columns.lon] = location?.longitude
        container[Columns.horizontalAccuracy] = location?.horizontalAccuracy
        container[Columns.placeName] = location?.placeName
        if let exif {
            container[Columns.exifJson] = String(data: try JSONEncoder().encode(exif), encoding: .utf8)
        }
        container[Columns.note] = note
        container[Columns.deletedAt] = deletedAt?.timeIntervalSince1970
    }
}
```

Session 모델도 동일 패턴 (createdAt/endedAt/deletedAt 모두 Int64 매핑). 단위 테스트로 round-trip 검증 (Task 1.3 끝 step에 추가).

각 파일은 단일 책임 (각 50~100 lines).

- [ ] **Step 2: 빌드 검증**

```bash
xcodegen generate && \
xcodebuild -scheme Camork \
  -destination "platform=iOS Simulator,name=$CAMORK_SIM" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
  build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: 커밋**

```bash
git add Camork/Storage/ Camork.xcodeproj/
git commit -F- <<'EOF'
add Photo, Session, LocationSnapshot, MediaKind, ExifData models with GRDB codecs

Plan B Phase 1.3 — 5개 도메인 struct를 Sendable + GRDB FetchableRecord +
PersistableRecord로 정의. LocationSnapshot은 embed columns(firstLat 등)로 풀어
GRDB 표준 매핑.

Constraint: 모두 Sendable, MediaKind는 v1 Core photo only (ADR #11 + CHECK 제약과 일치), ExifData는 JSON blob 직렬화 (인덱스 불필요)
Rejected: LocationSnapshot 별도 테이블 — N+1 쿼리 + 과한 정규화
Rejected: MediaKind에 video case 미리 두기 — v1.2에서 migration v3 + enum 동시 변경
Confidence: high
Scope-risk: narrow
Directive: Phase 1.4 MediaStorage actor가 본 모델을 GRDB API로 read/write
Tested: 빌드 검증
Not-tested: 실제 GRDB persist/fetch — Phase 1.5에서
EOF
```

---

### Task 1.4 — FileOps protocol + MediaFileSystem (C5 정정)

**Files:**
- Create: `Camork/Storage/FileOps.swift`           — protocol (test seam)
- Create: `Camork/Storage/MediaFileSystem.swift`   — concrete impl, init throws (C5)
- Test: `CamorkTests/MediaFileSystemTests.swift`

**C5 정정**: 
- `MediaFileSystem.init`은 `try?`로 bootstrap error를 swallow하지 않음 → **`init(root:) throws`**.
- Failure matrix 테스트를 위한 **`protocol FileOps`** 도입 — production은 `MediaFileSystem`, test는 `FakeFileOps`로 staging write/mv/final-delete 실패를 강제할 수 있게.

```swift
// Camork/Storage/FileOps.swift
import Foundation

protocol FileOps: Sendable {
    func writeStaging(fileName: String, data: Data) throws
    func moveStagingToFinal(fileName: String) throws
    func removeStaging(fileName: String) throws
    func removeFinal(fileName: String) throws
    func stagingExists(fileName: String) throws -> Bool
    func finalExists(fileName: String) throws -> Bool
    func enumerateFinal() throws -> [String]
}
```

```swift
// Camork/Storage/MediaFileSystem.swift (C5 — init throws)
struct MediaFileSystem: FileOps {
    let root: URL  // 보통 Application Support/Camork

    init(root: URL) throws {
        self.root = root
        try Self.bootstrap(root: root)   // C5: 에러 swallow 금지
    }

    static func bootstrap(root: URL) throws { /* 기존 로직 */ }
    // ... 나머지 FileOps 구현
}
```

- [ ] **Step 1: 실패 테스트**

```swift
// CamorkTests/MediaFileSystemTests.swift
@Suite("MediaFileSystem")
struct MediaFileSystemTests {
    @Test("staging write 후 final로 mv 성공")
    func stagingToFinalSuccess() throws {
        let fs = MediaFileSystem(root: tempDir())
        try fs.writeStaging(fileName: "abc.heic", data: Data([1,2,3]))
        try fs.moveStagingToFinal(fileName: "abc.heic")
        #expect(try fs.finalDataExists(fileName: "abc.heic"))
        #expect(try !fs.stagingDataExists(fileName: "abc.heic"))
    }

    @Test("staging cleanup")
    func stagingCleanup() throws {
        let fs = MediaFileSystem(root: tempDir())
        try fs.writeStaging(fileName: "abc.heic", data: Data([1,2,3]))
        try fs.removeStaging(fileName: "abc.heic")
        #expect(try !fs.stagingDataExists(fileName: "abc.heic"))
    }

    @Test("Media root에 isExcludedFromBackup 플래그")
    func excludedFromBackup() throws {
        let root = tempDir()
        _ = MediaFileSystem(root: root)
        let values = try root.appendingPathComponent("Media").resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    // ... 5건 정도
}

private func tempDir() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
}
```

- [ ] **Step 2~5**: 실패 확인 → 구현 → 통과 → 커밋 (Lore)

```swift
// Camork/Storage/MediaFileSystem.swift  (C5: init throws, FileOps 채택)
import Foundation

struct MediaFileSystem: FileOps {
    let root: URL  // 보통 Application Support/Camork

    init(root: URL) throws {
        self.root = root
        try Self.bootstrap(root: root)   // C5: 에러 swallow 금지
    }

    static func bootstrap(root: URL) throws {
        for sub in ["Media", "Media/.staging"] {
            var dir = root.appendingPathComponent(sub, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try dir.setResourceValues(values)
        }
    }

    func writeStaging(fileName: String, data: Data) throws {
        let url = root.appendingPathComponent("Media/.staging/\(fileName)")
        try data.write(to: url, options: .atomic)
    }

    func moveStagingToFinal(fileName: String) throws {
        let from = root.appendingPathComponent("Media/.staging/\(fileName)")
        let to = root.appendingPathComponent("Media/\(fileName)")
        try FileManager.default.moveItem(at: from, to: to)
    }

    func removeStaging(fileName: String) throws { /* ... */ }
    func removeFinal(fileName: String) throws { /* ... */ }
    func stagingDataExists(fileName: String) throws -> Bool { /* ... */ }
    func finalDataExists(fileName: String) throws -> Bool { /* ... */ }
    func enumerateFinal() throws -> [String] { /* ... */ }
}
```

---

### Task 1.5 — SessionAssignmentPolicy (pure helper) + 6 edge case 테스트

**Files:**
- Create: `Camork/Sessions/PhotoCapturePayload.swift`
- Create: `Camork/Sessions/SessionAssignmentPolicy.swift`
- Test: `CamorkTests/SessionAssignmentPolicyTests.swift`

- [ ] **Step 1: 실패 테스트** (6 edge case + 경계 + nil)

```swift
@Suite("SessionAssignmentPolicy")
struct SessionAssignmentPolicyTests {
    let policy = SessionAssignmentPolicy()

    @Test("case a: GPS latency — current location nil이면 거리 규칙 skip")
    func caseA_gpsLatency() {
        let previous = makePhoto(at: Date(timeIntervalSince1970: 0), loc: snap(lat: 0, lon: 0, acc: 10))
        let current = makePayload(at: Date(timeIntervalSince1970: 60), loc: nil)
        let result = policy.decideSession(previous: previous, current: current, manualFlag: false)
        #expect(result == .continueSession(sessionId: previous.sessionId))
    }

    @Test("case b: 위치 권한 거부 — 시간 규칙만 적용")
    func caseB_locationDenied() { /* ... */ }

    @Test("case c: 첫 촬영 — 새 세션")
    func caseC_firstCapture() {
        let result = policy.decideSession(previous: nil, current: makePayload(...), manualFlag: false)
        #expect(result == .newSession)
    }

    @Test("case d: manualFlag true — 무조건 새 세션, GPS/시간 무시")
    func caseD_manualFlag() {
        let previous = makePhoto(...)  // 같은 자리, 직전
        let current = makePayload(...)
        let result = policy.decideSession(previous: previous, current: current, manualFlag: true)
        #expect(result == .newSession)
    }

    @Test("case e: 30분 이상 무촬영 — 새 세션")
    func caseE_thirtyMinutes() { /* ... */ }

    @Test("case f: manualFlag + 50m 이동 + 30분 경과 — 새 세션 1개")
    func caseF_combined() { /* ... */ }

    // 경계 테스트
    @Test("거리 49m vs 50m vs 51m")
    func distanceBoundary() { /* 3 cases */ }

    @Test("시간 29분 vs 30분 vs 31분")
    func timeBoundary() { /* 3 cases */ }

    @Test("horizontalAccuracy 25/30/35m — 30m 초과면 거리 규칙 skip")
    func accuracyBoundary() { /* 3 cases */ }

    @Test("horizontalAccuracy nil — 거리 규칙 skip, 시간 규칙으로 fallback")
    func accuracyNil() { /* ... */ }
}
```

- [ ] **Step 2~5**: 실패 → 구현 (spec v3.3 §5.1 pseudocode 그대로) → 통과 → 커밋

```swift
// Camork/Sessions/SessionAssignmentPolicy.swift
struct SessionAssignmentPolicy: Sendable {
    enum Decision: Equatable, Sendable {
        case newSession
        case continueSession(sessionId: UUID)
    }

    func decideSession(
        previous: Photo?,
        current: PhotoCapturePayload,
        manualFlag: Bool
    ) -> Decision {
        if manualFlag { return .newSession }
        guard let previous = previous else { return .newSession }

        if let prevLoc = previous.location,
           let currLoc = current.location,
           prevLoc.horizontalAccuracy <= 30,
           currLoc.horizontalAccuracy <= 30 {
            if haversineDistance(prevLoc, currLoc) >= 50 {
                return .newSession
            }
        }

        let elapsed = current.capturedAt.timeIntervalSince(previous.capturedAt)
        if elapsed >= 30 * 60 { return .newSession }

        return .continueSession(sessionId: previous.sessionId)
    }
}

private func haversineDistance(_ a: LocationSnapshot, _ b: LocationSnapshot) -> Double {
    // 표준 haversine 공식
}
```

Lore commit.

---

### Task 1.6 — MediaStorage actor (saveCapture + Orphan reaper + 결정적 race/failure 테스트, C5+C6)

**Files:**
- Create: `Camork/Sessions/MediaStorage.swift`
- Create: `Camork/Sessions/MediaStorageTestHooks.swift`   [`#if DEBUG` only, C5]
- Test: `CamorkTests/MediaStorageTests.swift`

**C5 정정 (deterministic test hooks)**: `Task { saveCapture }` + `markPendingNewSession()` 만으로는 happens-before 순서를 보장 못함. `MediaStorageTestHooks` (test-only) 도입:

```swift
// Camork/Sessions/MediaStorageTestHooks.swift
#if DEBUG
struct MediaStorageTestHooks: Sendable {
    var afterManualFlagSnapshot: (@Sendable () async -> Void)?  // gate for race tests
    var beforeDBCommit: (@Sendable () async -> Void)?          // failure injection / ordering
    var forceFinalRemoveFailure: Bool = false                  // cleanup branch test
}
#endif
```

MediaStorage init에 `#if DEBUG` parameter:
```swift
actor MediaStorage {
    private var pendingManualSessionStart = false
    private let db: any DatabaseWriter
    private let fs: any FileOps   // C5: protocol으로 test 가능
    private let policy: SessionAssignmentPolicy

    #if DEBUG
    var testHooks: MediaStorageTestHooks = .init()
    #endif

    init(db: any DatabaseWriter, fs: any FileOps, policy: SessionAssignmentPolicy = .init()) {
        self.db = db; self.fs = fs; self.policy = policy
    }
    // ...
}
```

**C6 정정 (closure에 self 캡쳐 금지)**: GRDB write closure 안에서 `self.policy`/`self.resolveSessionId` 직접 접근 금지. snapshot + free function으로 분리.

(가장 큰 task. spec v3.3 §5.3 sample code 그대로 구현. 단계별 step.)

- [ ] **Step 1: 실패 테스트** (saveCapture + Failure matrix + Reaper + **in-flight race**)

```swift
@Suite("MediaStorage")
struct MediaStorageTests {
    func makeStorage() async throws -> (MediaStorage, DatabaseQueue, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let db = try DatabaseQueue()
        try Migrations.register(on: db)
        let fs = MediaFileSystem(root: dir)
        let storage = MediaStorage(db: db, fs: fs)
        return (storage, db, dir)
    }

    @Test("첫 saveCapture — 새 Session + Photo insert + 파일 final/")
    func firstCapture() async throws { /* ... */ }

    @Test("연속 saveCapture — 같은 세션에 누적")
    func continueSession() async throws { /* ... */ }

    @Test("Failure matrix: staging write fail — 잔존물 없음")
    func failureStagingWrite() async throws { /* ... */ }

    @Test("Failure matrix: mv fail — staging cleanup")
    func failureMv() async throws { /* ... */ }

    @Test("Failure matrix: DB commit fail — final orphan은 best-effort 삭제")
    func failureCommit() async throws { /* ... */ }

    @Test("Failure matrix: crash 시뮬 (mv 후 commit 직전) — reaper가 final orphan 정리")
    func failureCrashAfterMv() async throws { /* ... */ }

    @Test("Orphan reaper — Media/에 있지만 DB row 없는 파일 삭제")
    func reaperOrphan() async throws { /* ... */ }

    @Test("Race: captured manualFlag == false, beforeDBCommit hook에서 markPending — commit 후 new flag 유지 (C5 결정적)")
    func raceManualFlagSetDuringInFlight() async throws {
        let (storage, _, _) = try await makeStorage()

        // C5: deterministic gate — beforeDBCommit hook에서 mark 호출
        await storage.installTestHook(beforeDBCommit: { [storage] in
            await storage.markPendingNewSession()
        })

        let photo = try await storage.saveCapture(makePayload())
        #expect(photo.sessionId != nil)
        // beforeDBCommit hook에서 set된 flag는 1st save가 wipe하지 않아야 함
        #expect(await storage.isPendingNewSession() == true)
    }

    @Test("Failure matrix: mv 실패 (FakeFileOps) → staging cleanup + abort")
    func failureMvDeterministic() async throws {
        let fakeFs = FakeFileOps(failOn: .moveStagingToFinal)
        let storage = makeStorage(fs: fakeFs)
        await #expect(throws: FakeFileOpsError.self) {
            _ = try await storage.saveCapture(makePayload())
        }
        #expect(fakeFs.stagingCleanupCalled)
    }

    @Test("Failure matrix: DB transaction fail → final 파일 best-effort 삭제")
    func failureDBTransaction() async throws {
        // DB closure 안에서 강제 throw로 transaction abort 시뮬
        // ...
    }

    @Test("Race-style: captured manualFlag == true 두 번 connsecutive saveCapture — 첫 save는 new session, 두 번째 save는 manualFlag 사용 안 함 (consumed flag 깨끗)")
    func consumedFlagClearAfterTrueSave() async throws { /* ... */ }

    @Test("Reentrancy: GRDB transaction 안에서 actor state 직접 접근 X — captured manualFlag만 사용")
    func reentrancyCapturedFlagOnly() async throws { /* ... */ }
}
```

- [ ] **Step 2~5**: 실패 → MediaStorage 구현 (spec v3.3 §5.3 sample code 채택) → 통과 → 커밋

핵심 구현 (C6 — closure에 self 캡쳐 금지):

```swift
// Camork/Sessions/MediaStorage.swift

// C6: DB helpers는 free functions / static — closure에서 self 의존성 제거
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
        id: id, sessionId: sessionId, fileName: fileName,
        thumbnailFileName: nil, kind: .photo,
        capturedAt: payload.capturedAt,
        location: payload.location, exif: payload.exif
    )
    try photo.insert(db)
    return photo
}

actor MediaStorage {
    private var pendingManualSessionStart: Bool = false
    private let db: any DatabaseWriter
    private let fs: any FileOps   // C5 protocol
    private let policy: SessionAssignmentPolicy

    #if DEBUG
    var testHooks: MediaStorageTestHooks = .init()
    #endif

    init(db: any DatabaseWriter, fs: any FileOps, policy: SessionAssignmentPolicy = .init()) {
        self.db = db; self.fs = fs; self.policy = policy
    }

    func markPendingNewSession() { pendingManualSessionStart = true }
    func isPendingNewSession() -> Bool { pendingManualSessionStart }

    func saveCapture(_ payload: PhotoCapturePayload) async throws -> Photo {
        // Step 0: manualFlag snapshot (actor isolation, await 전)
        let manualFlag = pendingManualSessionStart

        #if DEBUG
        if let hook = testHooks.afterManualFlagSnapshot { await hook() }
        #endif

        // Step 1: allocate id/path
        let photoId = UUID()
        let fileName = "\(photoId.uuidString).heic"

        // Step 2: staging write (GRDB transaction 밖)
        try fs.writeStaging(fileName: fileName, data: payload.imageData)

        // Step 3: atomic mv → final
        do {
            try fs.moveStagingToFinal(fileName: fileName)
        } catch {
            try? fs.removeStaging(fileName: fileName)
            throw error
        }

        #if DEBUG
        if let hook = testHooks.beforeDBCommit { await hook() }
        #endif

        // Step 4: GRDB transaction — C6: self 캡쳐 X, snapshot + free functions
        let policy = self.policy   // C6: snapshot before await
        let photo: Photo
        do {
            photo = try await db.write { [manualFlag, policy, photoId, fileName] db in
                let previous = try fetchLatestPhoto(db: db)
                let decision = policy.decideSession(
                    previous: previous,
                    current: payload,
                    manualFlag: manualFlag
                )
                let sessionId = try resolveSessionId(decision: decision, payload: payload, db: db)
                return try insertPhoto(
                    id: photoId, fileName: fileName,
                    payload: payload, sessionId: sessionId, db: db
                )
            }
        } catch {
            // Failure matrix: GRDB transaction fail — best-effort final 삭제, reaper로 cover
            try? fs.removeFinal(fileName: fileName)
            throw error
        }

        // Step 5: consumed flag만 clear (in-flight markPending wipe 방지)
        if manualFlag {
            pendingManualSessionStart = false
        }
        return photo
    }

    func runReaper() async throws { /* DB enumerate + fs.enumerateFinal 비교 */ }
    func fetchPhoto(id: UUID) async throws -> Photo? { /* ... */ }
    func updatePhotoNote(photoId: UUID, note: String?) async throws { /* ... */ }
}
```

**핵심 C6 변경**: GRDB closure는 `[manualFlag, policy, photoId, fileName]` capture만 사용. `self` 미참조. DB helpers는 free functions (`fetchLatestPhoto`, `resolveSessionId`, `insertPhoto`).

Lore commit. **Phase 1 완료** — `xcodebuild test`로 Plan A 7건 + Phase 1 신규 ~30건 통과 검증.

---

## Phase 2 — Camera 캡처 + UI (v1.1 — task-level expansion, C4)

### Task 2a.1 — PermissionsService + 단위 테스트

**Files:**
- Create: `Camork/Services/PermissionsService.swift`
- Test: `CamorkTests/PermissionsServiceTests.swift`

- [ ] **Step 1: 실패 테스트**

```swift
@Suite("PermissionsService")
struct PermissionsServiceTests {
    @Test("AVAuthorizationStatus → PermissionState 매핑 — granted")
    func cameraGranted() {
        let state = PermissionsService.map(camera: .authorized)
        #expect(state == .granted)
    }
    @Test("notDetermined / denied / restricted 매핑")
    func cameraOthers() { /* 3 cases */ }
    @Test("CLAuthorizationStatus → location 매핑")
    func locationMapping() { /* 4 cases */ }
}
```

- [ ] **Step 2~5**: 실패 → PermissionsService 구현 (카메라/위치만, 마이크 X) → 통과 → Lore commit

```swift
enum PermissionState: Sendable { case granted, denied, notDetermined, restricted }

struct PermissionsService: Sendable {
    static func map(camera status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: .granted
        case .denied: .denied
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        @unknown default: .denied
        }
    }
    static func map(location status: CLAuthorizationStatus) -> PermissionState { /* ... */ }

    func cameraState() -> PermissionState { /* live query */ }
    func locationState() -> PermissionState { /* live query */ }

    func requestCamera() async -> PermissionState { /* ... */ }
    func requestLocation() async -> PermissionState { /* ... */ }
}
```

### Task 2a.2 — CameraSessionBuilder + ExifBuilder + 단위 테스트

**Files:**
- Create: `Camork/Camera/Internal/CameraSessionBuilder.swift`
- Create: `Camork/Camera/Internal/ExifBuilder.swift`
- Test: `CamorkTests/CameraSessionBuilderTests.swift`
- Test: `CamorkTests/ExifBuilderTests.swift`

- [ ] **Step 1: 실패 테스트**

```swift
@Suite("CameraSessionBuilder")
struct CameraSessionBuilderTests {
    @Test("default config: photo preset + AVCapturePhotoOutput + back camera input descriptor")
    func defaultConfig() {
        let config = CameraSessionBuilder.makeConfiguration(facing: .back)
        #expect(config.sessionPreset == .photo)
        #expect(config.outputs.contains(.photo))
        #expect(config.deviceFacing == .back)
    }
    @Test("front camera 전환")
    func frontFacing() { /* ... */ }
}

@Suite("ExifBuilder")
struct ExifBuilderTests {
    @Test("AVCapturePhoto의 metadata에서 ISO/shutterSpeed/aperture 추출")
    func extractsExifFields() { /* mock AVCapturePhoto metadata dict */ }
    @Test("metadata 누락 시 옵셔널 nil 유지")
    func missingFields() { /* ... */ }
}
```

- [ ] **Step 2~5**: 실패 → 구현 (pure builder, no AVCaptureSession 직접 생성) → 통과 → commit

### Task 2a.3 — CameraSession (AVFoundation thin wrapper)

**Files:**
- Create: `Camork/Camera/CameraSession.swift`

- [ ] **Step 1**: AVCaptureSession 인스턴스 owner. CameraSessionBuilder의 configuration을 받아 시작/정지. 단위 테스트 없음 (실기기 manual). 빌드 검증만.
- [ ] **Step 2**: Lore commit.

### Task 2b.1 — LocationService

**Files:**
- Create: `Camork/Services/LocationService.swift`
- Test: `CamorkTests/LocationServiceTests.swift`

- [ ] **Step 1: 실패 테스트**

```swift
@Suite("LocationService")
struct LocationServiceTests {
    @Test("권한 거부 상태에서 latestKnown은 nil")
    func deniedReturnsNil() { /* ... */ }
    @Test("CLLocationManager가 location 전달 시 latestKnown snapshot 갱신")
    func snapshotUpdate() { /* mock delegate callback */ }
    @Test("horizontalAccuracy 음수 시 invalid로 nil 반환")
    func invalidAccuracy() { /* ... */ }
}
```

- [ ] **Step 2~5**: CLLocationManagerDelegate 구현, sync snapshot getter (`func latestKnown() -> LocationSnapshot?`)

### Task 2b.2 — MediaCapture (delegate + Sendable payload + actor hop)

**Files:**
- Create: `Camork/Camera/MediaCapture.swift`

- [ ] **Step 1**: AVCapturePhotoCaptureDelegate. `photoOutput(_:didFinishProcessingPhoto:error:)` callback에서:
  1. `Data` 추출 (HEIC)
  2. `ExifBuilder.build(from: photo)` → ExifData
  3. `locationService.latestKnown()` 동기 호출 (callback queue에서)
  4. `PhotoCapturePayload` 조립
  5. `Task { [payload] in try await mediaStorage.saveCapture(payload) }` hop

- [ ] **Step 2**: 빌드 검증. 실제 capture 검증은 실기기 manual.
- [ ] **Step 3**: Lore commit (capture delegate + Sendable payload hop, AVCapturePhoto 직접 hop 금지 명시).

### Task 2c.1 — DependencyContainer

**Files:**
- Create: `Camork/AppShell/DependencyContainer.swift`

- [ ] **Step 1**: App root container. `MediaStorage`, `LocationService`, `PermissionsService`, `CameraSession` 보유. Singleton 금지 — App root에서 1회 생성 후 Environment로 전파.

```swift
@MainActor
final class DependencyContainer: ObservableObject {
    let mediaStorage: MediaStorage
    let locationService: LocationService
    let permissionsService: PermissionsService

    init() throws {
        let db = try CamorkDatabase.open()
        let fs = try MediaFileSystem(root: /* app support */)
        self.mediaStorage = MediaStorage(db: db, fs: fs)
        self.locationService = LocationService()
        self.permissionsService = PermissionsService()
    }
}

// CamorkApp.swift에서:
// @StateObject private var deps = try! DependencyContainer()
// RootTabView().environmentObject(deps)
```

- [ ] **Step 2**: CamorkApp.swift 업데이트 + RootTabView.swift environmentObject.
- [ ] **Step 3**: Lore commit.

### Task 2c.2 — CameraScreenViewState + 단위 테스트 (UI 분기 + chip in-flight)

**Files:**
- Create: `Camork/Camera/Internal/CameraScreenViewState.swift`
- Test: `CamorkTests/CameraScreenViewStateTests.swift`

- [ ] **Step 1: 실패 테스트**

```swift
@Suite("CameraScreenViewState")
struct CameraScreenViewStateTests {
    @Test("camera granted + pending false + not saving → cameraActive(.chipIdle)")
    func cameraActiveIdle() {
        let v = CameraScreenViewState.compute(
            camera: .granted, location: .granted,
            isPending: false, isInFlight: false
        )
        #expect(v == .cameraActive(chip: .idle))
    }
    @Test("camera denied → permissionDenied(.camera)")
    func cameraDenied() { /* ... */ }
    @Test("isPending true + in-flight false → cameraActive(.chipPending)")
    func chipPending() { /* ... */ }
    @Test("isInFlight true → cameraActive(.chipDisabled) regardless of isPending")
    func chipDisabledDuringSave() {
        // UI-level test (사용자 review 메모): in-flight 동안 chip ignored
        let v1 = CameraScreenViewState.compute(camera: .granted, location: .granted, isPending: false, isInFlight: true)
        let v2 = CameraScreenViewState.compute(camera: .granted, location: .granted, isPending: true, isInFlight: true)
        #expect(v1 == .cameraActive(chip: .disabled))
        #expect(v2 == .cameraActive(chip: .disabled))
    }
    @Test("camera notDetermined → requestPrompt")
    func requestPrompt() { /* ... */ }
}
```

- [ ] **Step 2~5**: 구현 + Lore commit

```swift
enum CameraScreenViewState: Equatable {
    case cameraActive(chip: ChipState)
    case permissionDenied(target: PermissionTarget)
    case requestPrompt
    case cameraInitError(reason: String)

    enum ChipState: Equatable { case idle, pending, disabled }
    enum PermissionTarget: Equatable { case camera, location }

    static func compute(
        camera: PermissionState, location: PermissionState,
        isPending: Bool, isInFlight: Bool
    ) -> CameraScreenViewState {
        // 분기 로직 (pure)
    }
}
```

### Task 2c.3 — CameraView (UIViewControllerRepresentable)

**Files:**
- Create: `Camork/Camera/CameraView.swift`

- [ ] **Step 1**: AVCaptureVideoPreviewLayer를 UIView로 래핑. SwiftUI binding은 CameraSession actor의 isRunning만 (minimal).
- [ ] **Step 2**: 빌드 검증 + Lore commit.

### Task 2c.4 — CameraScreen + ScenePhase hook

**Files:**
- Create: `Camork/Camera/CameraScreen.swift`
- Modify: `Camork/RootTabView.swift` — placeholder → 실제 CameraScreen

- [ ] **Step 1**: CameraScreen SwiftUI View. Environment에서 DependencyContainer 받음. `@State`로 `isInFlight: Bool` 관리. CameraScreenViewState.compute 결과로 layout 분기.

- [ ] **Step 2: ScenePhase hook**
```swift
@Environment(\.scenePhase) var scenePhase

.onChange(of: scenePhase) { _, phase in
    if phase == .background { Task { await cameraSession.stopRunning() } }
    if phase == .active && viewState == .cameraActive { Task { await cameraSession.startRunning() } }
}
```

- [ ] **Step 3**: 셔터 탭 → `isInFlight = true` → MediaCapture trigger → `Task { await mediaStorage.saveCapture(...) }` → `isInFlight = false`.

- [ ] **Step 4**: "새 현장" 칩 — disabled when isInFlight, otherwise `await mediaStorage.markPendingNewSession()`.

- [ ] **Step 5**: 좌하단 thumb — 직전 사진 (mediaStorage.fetchLatest()). 탭 시 PhotoDetail 진입 (Phase 3).

- [ ] **Step 6**: Preview Dark/Light/AX5 + 권한 거부 variant.

- [ ] **Step 7**: 빌드 + 시뮬레이터 검증 (cameraInitError UI 보임) + Lore commit.

### Task 2c.5 — RootTabView 카메라 탭 placeholder 교체 + 빌드 검증

**Files:**
- Modify: `Camork/RootTabView.swift`

- [ ] **Step 1**: `CameraPlaceholderView()` → `CameraScreen()`.
- [ ] **Step 2**: 시뮬레이터 build/run + 시각 검증 (다크/라이트/AX5).
- [ ] **Step 3**: Lore commit + Phase 2 완료.

**Phase 2 완료 기준**: 시뮬레이터 build/run + 권한 UI + (`#if DEBUG`) seeded capture로 DB insert/PhotoDetail 진입 검증. 실제 카메라 capture는 실기기 manual (Phase 4).

---

## Phase 3 — PhotoDetail + 메모 (v1.1 — task-level expansion, C4)

### Task 3.1 — PhotoMemoEditor + 단위 테스트

**Files:**
- Create: `Camork/Sessions/PhotoMemoEditor.swift`   (C3: 단일 Sessions/ block)
- Test: `CamorkTests/PhotoMemoEditorTests.swift`

- [ ] **Step 1: 실패 테스트**

```swift
@Suite("PhotoMemoEditor")
struct PhotoMemoEditorTests {
    @Test("note update 후 fetchPhoto에서 동일 값")
    func updateAndReload() async throws { /* ... */ }
    @Test("note = nil로 설정")
    func clearToNil() async throws { /* ... */ }
    @Test("photoId not found → throws PhotoMemoEditor.Error.notFound")
    func notFound() async throws { /* ... */ }
}
```

- [ ] **Step 2~5**: 구현 (MediaStorage.updatePhotoNote 위임) + Lore commit

### Task 3.2 — PhotoDetailView (full-screen + 메모 sheet)

**Files:**
- Create: `Camork/Gallery/PhotoDetailView.swift`

- [ ] **Step 1**: SwiftUI View. fullScreenCover로 thumb 탭 시 진입. `@State var note: String`, `@State var showMemoSheet: Bool`.

- [ ] **Step 2**: Zoomable image (ScrollView + UIScrollView wrapper or native magnification).

- [ ] **Step 3**: 하단 메타 (시간/지역/사진수).

- [ ] **Step 4**: 메모 편집 sheet — TextEditor + 닫기 시 PhotoMemoEditor.update.

- [ ] **Step 5**: Preview Dark/Light/AX5 (seeded photo로).

- [ ] **Step 6**: CameraScreen의 thumb 탭 → PhotoDetailView 진입 (sheet binding).

- [ ] **Step 7**: 빌드 + 시뮬레이터 (seeded capture 후 thumb 탭 → 풀스크린 → 메모 입력 → 재진입 검증) + Lore commit.

**Phase 3 완료 기준**: 시뮬레이터에서 seeded capture → thumb → PhotoDetail → 메모 편집 → 저장 → 재진입 시 메모 유지.

---

## Phase 4 — 통합 회귀 + 실기기 manual + 완료 보고서

### Task 4.1 — 클린 빌드 + 전체 회귀 테스트

```bash
xcodegen generate && \
xcodebuild clean -scheme Camork && \
xcodebuild -scheme Camork \
  -destination "platform=iOS Simulator,name=$CAMORK_SIM" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
  test 2>&1 | tail -25
```

Expected: 모든 테스트 통과 (Plan A 7건 + Plan B ~40건+ = 47+건), 0 warnings, 0 failures.

### Task 4.2 — 실기기 manual checklist 실행

spec v3.3 §10 카테고리 5개 (lifecycle / 저장 / 세션 / detail / 비주얼) + §10.3.1 추가 시나리오 5건 모두 수행. 결과를 Phase 4 보고서에 첨부.

### Task 4.3 — Plan B 완료 보고서

**Files:**
- Create: `docs/superpowers/reports/2026-05-19-plan-B-storage-camera-complete.md`

내용:
- 산출 / 검증 결과 / commit 목록 / 실기기 manual 결과
- Plan C 인계 (spec v3.3 §13 + §14)
- 미해결 (출시 전): AccentColor hex / App Icon / 가림막 실구현 / Swift 6 전환 등 (Plan A 보고서 + Plan B 추가 발견)

---

## Plan B 완료 체크리스트

- [ ] Phase 1.0 ADR commit + 채택
- [ ] Phase 1.1 GRDB SPM dependency 추가
- [ ] Phase 1.2 Migrations + Database 골격
- [ ] Phase 1.3 모델 5개 (Photo/Session/LocationSnapshot/MediaKind/ExifData)
- [ ] Phase 1.4 MediaFileSystem
- [ ] Phase 1.5 SessionAssignmentPolicy + 단위 테스트 (6 edge case + 경계 + nil)
- [ ] Phase 1.6 MediaStorage actor + saveCapture + Reaper + race-style 테스트
- [ ] Phase 2a PermissionsService + CameraSessionBuilder
- [ ] Phase 2b MediaCapture + LocationService
- [ ] Phase 2c CameraScreen + ViewState + DependencyContainer + ScenePhase hook + chip in-flight ignore 테스트
- [ ] Phase 3.1 PhotoMemoEditor
- [ ] Phase 3.2 PhotoDetailView + thumb 탭 진입
- [ ] Phase 4.1 클린 회귀 47+건 통과
- [ ] Phase 4.2 실기기 manual checklist 실행
- [ ] Phase 4.3 완료 보고서 + Plan C 인계

**모두 통과 시 → Plan C (Gallery) 작성 단계.**

---

## 자주 쓰는 명령

```bash
export CAMORK_SIM="iPhone 17 Pro"   # 셸 시작 시 1회

# project.yml 수정 후
xcodegen generate

# 빌드
xcodebuild -scheme Camork \
  -destination "platform=iOS Simulator,name=$CAMORK_SIM" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
  build 2>&1 | tail -10

# 테스트
xcodebuild -scheme Camork \
  -destination "platform=iOS Simulator,name=$CAMORK_SIM" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
  test 2>&1 | tail -20
```

---

## 참고

- 부모 가이드: `/Users/jedel/Projects/CLAUDE.md`
- HIG: `.claude/references/apple-hig.md`
- 앱 가이드: `camork-ios/CLAUDE.md`
- spec v3.3: `docs/superpowers/specs/2026-05-19-camork-v1-core-B-storage-camera-design.md`
- Plan A 완료 보고서: `docs/superpowers/reports/2026-05-19-plan-A-setup-complete.md`
- ADR (Phase 1.0 산출): `docs/superpowers/adrs/2026-05-19-storage-and-concurrency.md`

---

## In-flight manualFlag 테스트 두 갈래 (사용자 메모 — Phase 1.6 + Phase 2c)

**Actor/storage 단위 테스트** (Phase 1.6 MediaStorageTests, C5 deterministic):
- captured manualFlag == false 시점에 saveCapture 호출 → `beforeDBCommit` hook에서 `markPendingNewSession()` 발생 → commit 후 새 flag가 wipe 안 되는지 검증.
- `MediaStorageTestHooks` (`#if DEBUG`)로 deterministic gate 제공.

**UI/view-state 단위 테스트** (Phase 2c CameraScreenViewStateTests):
- `isInFlight: true` 시 chip은 `.disabled` 상태 — `isPending` 값과 무관하게.
- 두 갈래가 분리되어 있어야 boolean flag 모델의 의도와 UX 약속이 모두 명시 검증됨.

---

## 부록 A — v1.1 정정 매핑 (ai-slop-cleaner workflow)

| # | 사용자 지적 | 반영 위치 |
|---|---|---|
| **C1** | GRDB 7.7.0 stale | Task 1.1 — v7.10.0 (공식 GitHub Releases 2026-02-15 검증) exactVersion pin. silent downgrade 금지. |
| **C2** | subagent-driven REQUIRED 표기 | 헤더 — `executing-plans` (Inline) 기본, subagent-driven은 명시 승인/독립 slice 전용 옵션. |
| **C3** | duplicate Sessions/ block | File Structure — `PhotoMemoEditor.swift`를 `Sessions/` 단일 block으로 병합. |
| **C4** | Phase 2/3 skeletal | Phase 2a/2b/2c (10 task) + Phase 3.1/3.2 (8 task) — 각 task에 files/실패 테스트/구현/검증/Lore commit step. |
| **C5** | race/failure 테스트 비결정적 | `MediaStorageTestHooks` (`#if DEBUG`) + `FileOps` protocol + `MediaFileSystem.init throws` (try? 제거). |
| **C6** | closure에 `self.policy` 등 캡쳐 | DB helpers를 free functions (`fetchLatestPhoto`/`resolveSessionId`/`insertPhoto`). closure capture는 `[manualFlag, policy, photoId, fileName]`만, self 미참조. |
| **C7** | `db.schemaVersion()` API misuse | `Migrations.makeMigrator()` 노출 → test는 `DatabaseMigrator.appliedIdentifiers(_:)` 사용. |
| **C8** | Date ↔ Int64 codec 미정 | Task 1.3 — 각 모델에 `Columns` enum + `init(row:)`/`encode(to:)`로 `Date.timeIntervalSince1970` 명시 매핑. |
| **S1** | XcodeGen package product | Task 1.1 — `url: ...git`, `product: GRDB` 명시. |
