# Camork v1 Core — Plan B: Storage + Camera Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

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
│  ├─ Migrations.swift               — migration v1 (Photo, Session)
│  ├─ MediaFileSystem.swift          — staging/.staging/final/thumbnail 디렉토리 관리
│  ├─ Photo.swift                    — struct + GRDB codec
│  ├─ Session.swift                  — struct + GRDB codec
│  ├─ LocationSnapshot.swift         — struct, embed columns
│  ├─ MediaKind.swift                — enum (photo only, CHECK 제약과 일치)
│  └─ ExifData.swift                 — struct, JSON blob 직렬화
├─ Sessions/                         [신규 — Phase 1.3, 1.4]
│  ├─ PhotoCapturePayload.swift      — Sendable struct (callback → actor hop)
│  ├─ SessionAssignmentPolicy.swift  — pure helper, decideSession
│  └─ MediaStorage.swift             — actor (단일 writer + saveCapture + Orphan reaper)
├─ Services/                         [신규 — Phase 2a, 2b]
│  ├─ PermissionsService.swift       — 카메라/위치 권한 매핑 (마이크 제외)
│  └─ LocationService.swift          — CLLocationManager, latest known snapshot
├─ Camera/                           [신규 — Phase 2]
│  ├─ CameraSession.swift            — AVCaptureSession thin wrapper
│  ├─ MediaCapture.swift             — AVCapturePhotoCaptureDelegate, Sendable payload 변환
│  ├─ CameraView.swift               — UIViewControllerRepresentable (preview layer)
│  ├─ CameraScreen.swift             — 메인 카메라 화면 (@MainActor SwiftUI View)
│  └─ Internal/                      — 비즈니스 로직 (단위 테스트 대상)
│     ├─ CameraScreenViewState.swift — permission state → UI variant + chip pending
│     ├─ CameraSessionBuilder.swift  — AVCaptureSession configuration 빌더 (pure)
│     └─ ExifBuilder.swift           — AVCapturePhoto → ExifData
├─ Gallery/                          [신규 — Phase 3 (Plan C에서 확장)]
│  └─ PhotoDetailView.swift          — 단일 사진 풀스크린 + 메모 sheet
├─ Sessions/                         [Phase 3 추가]
│  └─ PhotoMemoEditor.swift          — 메모 update 로직 (테스트 대상)
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

- [ ] **Step 1: project.yml에 GRDB SPM 추가**

```yaml
packages:
  GRDB:
    url: https://github.com/groue/GRDB.swift
    exactVersion: "7.7.0"   # 작업 시점 latest stable 확인 후 고정

targets:
  Camork:
    # ... 기존 설정 ...
    dependencies:
      - package: GRDB
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
add GRDB.swift SPM dependency with pinned exactVersion

Plan B Phase 1.1 — GRDB는 메타데이터 DB 전용. exactVersion으로 Package.resolved
고정해 dependency drift 방지.

Constraint: exactVersion 고정 (ADR 결정 #1), GRDB는 metadata only (미디어는 파일 시스템)
Rejected: "from:" 범위 의존성 — minor 변화로 빌드 깨질 가능성
Confidence: high
Scope-risk: narrow
Directive: 후속 task에서 GRDB import + DatabaseWriter 사용
Tested: xcodebuild build SUCCEEDED, GRDB import 가능
Not-tested: 실제 GRDB API 동작 — Task 1.2 Database.swift 작성 시 검증
EOF
```

---

### Task 1.2 — Migrations + Database 골격

**Files:**
- Create: `Camork/Storage/Database.swift`
- Create: `Camork/Storage/Migrations.swift`
- Test: `CamorkTests/MigrationsTests.swift`

- [ ] **Step 1: 실패 테스트** (Migration idempotent + schema 생성)

```swift
// CamorkTests/MigrationsTests.swift
import Testing
import GRDB
@testable import Camork

@Suite("Migrations")
struct MigrationsTests {
    @Test("migration v1을 두 번 호출해도 schemaVersion 변화 없음")
    func idempotent() throws {
        let db = try DatabaseQueue()
        try Migrations.register(on: db)
        let firstVersion = try db.read { try $0.schemaVersion() }

        try Migrations.register(on: db)
        let secondVersion = try db.read { try $0.schemaVersion() }

        #expect(firstVersion == secondVersion)
    }

    @Test("v1 schema 생성 후 Session/Photo 테이블 존재")
    func schemaCreated() throws {
        let db = try DatabaseQueue()
        try Migrations.register(on: db)

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
        try Migrations.register(on: db)

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
        try Migrations.register(on: queue)
        return queue
    }
}
```

```swift
// Camork/Storage/Migrations.swift
import GRDB

enum Migrations {
    static func register(on writer: any DatabaseWriter) throws {
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

        try migrator.migrate(writer)
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

### Task 1.3 — 모델 (Photo, Session, LocationSnapshot, MediaKind, ExifData)

**Files:**
- Create: `Camork/Storage/Photo.swift`
- Create: `Camork/Storage/Session.swift`
- Create: `Camork/Storage/LocationSnapshot.swift`
- Create: `Camork/Storage/MediaKind.swift`
- Create: `Camork/Storage/ExifData.swift`

- [ ] **Step 1: 5개 파일 작성**

(spec v3.3 §3.2 Swift 모델 참조. 각 struct에 `FetchableRecord, PersistableRecord, Codable, Sendable` 채택. LocationSnapshot은 embed columns로 풀어 GRDB column 매핑.)

각 파일은 단일 책임 (각 30~60 lines).

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

### Task 1.4 — MediaFileSystem (staging/final/thumbnail 디렉토리 관리)

**Files:**
- Create: `Camork/Storage/MediaFileSystem.swift`
- Test: `CamorkTests/MediaFileSystemTests.swift`

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
// Camork/Storage/MediaFileSystem.swift
import Foundation

struct MediaFileSystem: Sendable {
    let root: URL  // 보통 Application Support/Camork

    init(root: URL) {
        self.root = root
        try? Self.bootstrap(root: root)
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

### Task 1.6 — MediaStorage actor (saveCapture + Orphan reaper + 단위 테스트)

**Files:**
- Create: `Camork/Sessions/MediaStorage.swift`
- Test: `CamorkTests/MediaStorageTests.swift`

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

    @Test("Race-style: captured manualFlag == false, in-flight 중 markPending — commit 후 new flag 유지")
    func raceManualFlagSetDuringInFlight() async throws {
        let (storage, db, _) = try await makeStorage()
        // 1st save: manualFlag == false
        let saveTask = Task { try await storage.saveCapture(makePayload()) }
        // in-flight 중 새 mark
        await storage.markPendingNewSession()
        _ = try await saveTask.value
        // 1st save commit 후에도 flag 유지되어야 함
        #expect(await storage.isPendingNewSession() == true)
    }

    @Test("Race-style: captured manualFlag == true 두 번 connsecutive saveCapture — 첫 save는 new session, 두 번째 save는 manualFlag 사용 안 함 (consumed flag 깨끗)")
    func consumedFlagClearAfterTrueSave() async throws { /* ... */ }

    @Test("Reentrancy: GRDB transaction 안에서 actor state 직접 접근 X — captured manualFlag만 사용")
    func reentrancyCapturedFlagOnly() async throws { /* ... */ }
}
```

- [ ] **Step 2~5**: 실패 → MediaStorage 구현 (spec v3.3 §5.3 sample code 채택) → 통과 → 커밋

핵심 구현:
```swift
actor MediaStorage {
    private var pendingManualSessionStart: Bool = false
    private let db: any DatabaseWriter
    private let fs: MediaFileSystem
    private let policy: SessionAssignmentPolicy

    init(db: any DatabaseWriter, fs: MediaFileSystem, policy: SessionAssignmentPolicy = .init()) {
        self.db = db; self.fs = fs; self.policy = policy
    }

    func markPendingNewSession() { pendingManualSessionStart = true }
    func isPendingNewSession() -> Bool { pendingManualSessionStart }

    func saveCapture(_ payload: PhotoCapturePayload) async throws -> Photo {
        let manualFlag = pendingManualSessionStart  // snapshot (Step 0)

        let photoId = UUID()
        let fileName = "\(photoId.uuidString).heic"

        try fs.writeStaging(fileName: fileName, data: payload.imageData)
        do {
            try fs.moveStagingToFinal(fileName: fileName)
        } catch {
            try? fs.removeStaging(fileName: fileName)
            throw error
        }

        let photo: Photo
        do {
            photo = try await db.write { [manualFlag] db in
                let previous = try Photo
                    .order(Column("capturedAt").desc)
                    .filter(Column("deletedAt") == nil)
                    .fetchOne(db)
                let decision = self.policy.decideSession(
                    previous: previous,
                    current: payload,
                    manualFlag: manualFlag
                )
                let sessionId = try self.resolveSessionId(decision: decision, payload: payload, db: db)
                let photo = Photo(
                    id: photoId, sessionId: sessionId, fileName: fileName,
                    kind: .photo, capturedAt: payload.capturedAt,
                    location: payload.location, exif: payload.exif
                )
                try photo.insert(db)
                return photo
            }
        } catch {
            try? fs.removeFinal(fileName: fileName)
            throw error
        }

        if manualFlag {
            pendingManualSessionStart = false
        }
        return photo
    }

    func runReaper() async throws { /* ... */ }
    func fetchPhoto(id: UUID) async throws -> Photo? { /* ... */ }
    func updatePhotoNote(photoId: UUID, note: String?) async throws { /* ... */ }
}
```

Lore commit. **Phase 1 완료** — `xcodebuild test`로 Plan A 7건 + Phase 1 신규 ~30건 통과 검증.

---

## Phase 2 — Camera 캡처 + UI

### Phase 2a — PermissionsService + CameraSessionBuilder + 단위 테스트

(Tasks 2a.1 ~ 2a.3)

- PermissionsService: 카메라/위치 권한 매핑 (마이크 제외). enum `PermissionState { granted, denied, notDetermined, restricted }`.
- CameraSessionBuilder: AVCaptureSession configuration (preset, AVCapturePhotoOutput, device input). pure builder, 결과는 configuration struct.
- 단위 테스트: 권한 상태 매핑, configuration 빌더 출력.

(상세 TDD step은 Plan A 패턴 답습.)

### Phase 2b — MediaCapture + LocationService

(Tasks 2b.1 ~ 2b.2)

- LocationService: CLLocationManager wrapper. `latestKnown()` 동기 snapshot getter. CLLocationManagerDelegate로 latest 갱신.
- MediaCapture: AVCapturePhotoCaptureDelegate. callback queue에서 `Data` + ExifBuilder.build(photo) + LocationService.latestKnown() → `PhotoCapturePayload` 조립. `Task { [payload] in await mediaStorage.saveCapture(payload) }` hop.

### Phase 2c — Camera UI + CameraScreenViewState + DependencyContainer + ScenePhase hook

(Tasks 2c.1 ~ 2c.5)

- DependencyContainer: App root container. `MediaStorage`, `LocationService`, `PermissionsService` 보유. Environment로 전파.
- CameraScreenViewState: 순수 함수 `viewState(permission:isPending:isSaving:) -> ViewState`. 단위 테스트로 모든 분기 검증.
- CameraScreen: SwiftUI View, Environment에서 dependencies 받음.
- **chip in-flight ignore 테스트** (사용자 메모): CameraScreenViewState 단위 테스트에 "saveCapture in-flight 동안 chip은 disabled 상태" 검증 추가.
- RootTabView의 placeholder를 실제 CameraScreen으로 교체.
- ScenePhase 감지 → `CameraSession.stopRunning()` hook.

**Phase 2 완료**: 시뮬레이터 build/run + 권한 UI + (test-only) `injectSeededCapture`로 DB insert 검증. 실제 카메라 capture는 실기기 manual.

---

## Phase 3 — PhotoDetail + 메모

### Task 3.1 — PhotoMemoEditor + 단위 테스트

- PhotoMemoEditor: `updateNote(photoId:note:)` 메서드 (MediaStorage 위임). nil 처리.
- 단위 테스트: 메모 update + reload + nil 정책.

### Task 3.2 — PhotoDetailView

- `Camork/Gallery/PhotoDetailView.swift` — fullScreenCover, ZoomableScrollView, 메모 sheet (TextEditor).
- CameraScreen의 thumb 탭 → PhotoDetailView 진입.
- Preview Dark/Light/AX5.

**Phase 3 완료**: 시뮬레이터에서 seeded capture → thumb → PhotoDetail → 메모 편집 → 저장 → 재진입 검증.

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

**Actor/storage 단위 테스트** (Phase 1.6 MediaStorageTests):
- captured manualFlag == false 시점에 saveCapture 호출 → 진행 중 `markPendingNewSession()` 발생 → commit 후 새 flag가 wipe 안 되는지 검증 (race-style 테스트).

**UI/view-state 단위 테스트** (Phase 2c CameraScreenViewStateTests):
- saveCapture in-flight 동안 "새 현장" chip은 disabled / 탭 ignored 상태인지 검증 — captured manualFlag == true 시 두 번째 queued intent가 들어오지 않음을 UI 차원에서 보장.
- 두 갈래가 분리되어 있어야 boolean flag 모델의 의도와 UX 약속이 모두 명시 검증됨.
