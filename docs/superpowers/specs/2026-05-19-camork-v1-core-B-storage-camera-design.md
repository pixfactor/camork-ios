# Camork v1 Core — Plan B: Storage + Camera 설계서

- **작성일:** 2026-05-19
- **상태:** 초안 — spec review loop 대기
- **상속 컨텍스트:**
  - 공통 가이드: `/Users/jedel/Projects/CLAUDE.md`
  - HIG 시각: `.claude/references/apple-hig.md`
  - 앱 가이드: `camork-ios/CLAUDE.md`
  - 마스터 설계서: `docs/superpowers/specs/2026-05-19-camork-rebuild-design.md` (v2)
  - Plan A 완료 보고서: `docs/superpowers/reports/2026-05-19-plan-A-setup-complete.md`
  - Plan B 진입 전 결정 #1~#3 (implementation-notes 참조)

---

## 1. Goal / Scope / 완료 기준

### 1.1 Goal

Camork의 v1 Core 핵심 동작 — **촬영 → 자동 세션 묶음 → 로컬 저장 → 직전 사진 확인 → 메모 편집** — 의 첫 닫힌 루프를 구현한다. UI 시각화는 카메라 화면 단위와 PhotoDetail만, 나머지(갤러리/공유/AppLock)는 Plan C/D/E.

### 1.2 포함 (Plan B 산출 범위)

- **Storage 인프라**: GRDB.swift SPM 의존성, schema v1 migration, `actor MediaStorage`, `actor SessionManager`, 모델(`Photo`, `Session`), `LocationSnapshot`
- **카메라**: `PermissionsService` (카메라/위치/마이크 권한 흐름), `CameraSession` (AVCaptureSession thin wrapper), `MediaCapture` (AVCapturePhotoOutput → Sendable payload), 카메라 탭 UI
- **카메라 UI**: 뷰파인더, 셔터, 카메라 전환, 좌하단 직전 사진 thumb, 상단 "새 현장" 칩, 권한 거부 안내
- **PhotoDetail**: thumb 탭 시 단일 사진 풀스크린, 사진별 메모 편집(GRDB 저장)
- **세션 자동 묶기**: GPS 50m + horizontalAccuracy≤30m + 30분 무촬영 규칙, "새 현장" lazy 플래그 (6 edge case)
- **단위 테스트**: 순수 로직 (metadata builder, file naming, session assignment, permission state mapping, error mapping)
- **실기기 manual checklist**: AVCaptureSession lifecycle, 권한 거부 UX, 백그라운드 카메라 정지 (Plan B 보고서)

### 1.3 제외 (Plan C/D/E 영역)

| 영역 | 어디로 |
|---|---|
| 세션 리스트 / 세션 카드 / 갤러리 메인 화면 | Plan C |
| 폴더, 검색, 시간 필터, 지도 토글 | Plan C / Plan B 이후 |
| 다중 선택, 공유 준비 화면, EXIF stripping, iOS Share Sheet 위임 | Plan D |
| Face ID 잠금 / AppLock 정책 / 잠금 화면 | Plan E |
| `AppBackgroundShield` 실구현 (Plan A의 placeholder hook 유지) | Plan E |
| 휴지통, 30일 자동 삭제 | Plan C (`deletedAt` 컬럼은 schema에 미리 둠) |
| iCloud Drive 백업, CloudKit 동기화, App Icon, 동영상 | v1.2 / v2 |
| 영어 외 추가 언어 | v2 Trust |

### 1.4 완료 기준

- **Phase 1**: UI 없이 단위 테스트로만 검증. in-memory/temp DB, migration v1 통과, MediaStorage actor + SessionManager 자동 묶기 6 edge case 테스트 통과.
- **Phase 2**: 시뮬레이터 build/run 성공 + 카메라 탭이 placeholder가 아닌 실제 뷰파인더로 활성화 + 실기기 manual checklist 초안 작성.
- **Phase 3**: thumb 탭 → PhotoDetail 진입 + 메모 입력/저장/재로드 (시뮬레이터에서 검증 가능).
- **Phase 4**: clean test 회귀 + 실기기 manual checklist 실행 결과 첨부 + Plan C 인계 항목 정리.
- **commit**: 모든 commit은 Lore Commit Protocol (Plan A v3 Commit Policy 상속).

---

## 2. Phase 분할

### Phase 1 — Storage 인프라

**Phase 1.0 (필수 첫 task) — Storage + 동시성 단일 ADR**

문서 경로: `docs/superpowers/adrs/2026-05-19-storage-and-concurrency.md`

ADR 포함 사항 (결정 #3 7+5 가설을 정식화):
1. GRDB `DatabaseWriter` 선택 (DatabaseQueue vs DatabasePool 비교 + 채택 이유)
2. DB write vs 파일 IO 의 transaction/order 정책 (파일 먼저 → DB commit, 실패 시 orphan 처리)
3. `actor MediaStorage` 책임 경계 (DB connection + 파일 IO + thumbnail 생성)
4. `actor SessionManager` 책임 경계 (자동 묶기 + persist via MediaStorage)
5. `@MainActor` 적용 범위 (View / ViewModel / UI state만, 순수 domain model + repository protocol 제외)
6. AVFoundation callback → Sendable payload → `await actor.save(payload)` hop 규칙
7. Cross-actor 통신은 `await` 직접 호출, Combine/AsyncStream은 UI 구독에만
8. Reentrancy 정책 (await 전후 mutation 안 나누는 구조 우선, transaction/idempotency/snapshot으로 해결, Lock은 최후 수단)
9. 의존성 주입 (Singleton 금지 + App root container를 Environment로 흘리기 허용)
10. 테스트 전략 (in-memory DB로 actor 격리)

**Phase 1.1 — GRDB SPM + 기본 schema**

- SPM dependency 추가 (`Package.resolved` 버전 고정)
- `Camork/Storage/Database.swift` — DB open, `Library/Application Support/Camork/Metadata/camork.sqlite` (Data Protection class `.completeUntilFirstUserAuthentication`), `isExcludedFromBackup = true`
- `Camork/Storage/Migrations.swift` — migration v1: Session + Photo 테이블 생성

**Phase 1.2 — 모델 + 코덱**

- `Camork/Sessions/Session.swift` — struct, Codable, FetchableRecord, PersistableRecord
- `Camork/Storage/Photo.swift` — struct, GRDB 코덱
- `Camork/Storage/LocationSnapshot.swift` — struct, embed columns로 표현

**Phase 1.3 — `actor MediaStorage`**

- 파일 저장 (`Library/Application Support/Camork/Media/<UUID>.heic`)
- DB write (`Photo`, `Session`)
- thumbnail 생성 + 캐시 (`Library/Caches/Camork/Thumbnails/<UUID>.jpg`)
- `save(payload: PhotoCapturePayload) async throws -> Photo`
- 단위 테스트: in-memory DB + temp dir로 격리

**Phase 1.4 — `actor SessionManager`**

- 자동 묶기 로직 (Section 5 참조)
- `pendingManualSessionStart` 플래그 (in-memory, 프로세스 생존 동안)
- `assignToCurrentSession(...)` API
- `markPendingNewSession()` API ("새 현장" 칩에서 호출)
- 단위 테스트: 6 edge case 모두

### Phase 2 — Camera 캡처 + UI

**Phase 2a — PermissionsService + CameraSession 빌더**

- `Camork/Services/PermissionsService.swift` — 카메라/위치/마이크 권한 상태 매핑 (granted / denied / notDetermined / restricted)
- `Camork/Camera/CameraSession.swift` — AVCaptureSession configuration 빌더 (단위 테스트 대상)
- 권한 상태 → UI state 매핑 함수 (순수 로직, 테스트 가능)
- 단위 테스트: 권한 상태 매핑, configuration 빌더 출력

**Phase 2b — MediaCapture 저장 파이프라인 연결**

- `Camork/Camera/MediaCapture.swift` — `AVCapturePhotoCaptureDelegate`, callback에서 **`AVCapturePhoto`를 actor로 hop하지 않음**
- callback queue에서 `Data` + metadata만 뽑아 `PhotoCapturePayload` (Sendable struct) 만들기
- `Task { await mediaStorage.save(payload) }` 로 hop
- `Camork/Services/LocationService.swift` — CoreLocation latest known location 노출 (best-effort, 권한 없으면 nil)
- 통합 테스트: payload 생성 + actor 전달 mock (실제 캡처는 실기기)

**Phase 2c — Camera UI 연결**

- `Camork/Camera/CameraView.swift` — `UIViewControllerRepresentable`로 AVCaptureSession preview layer 래핑
- `Camork/Camera/CameraScreen.swift` — 메인 카메라 화면 (뷰파인더 + 셔터 + 카메라 전환 + 좌하단 thumb + 상단 "새 현장" 칩)
- `RootTabView` 카메라 탭 placeholder → 실제 `CameraScreen` 교체
- 권한 거부 시: `ContentUnavailableView` 변형으로 "설정 → Camork에서 카메라 권한 허용" + deeplink 버튼
- 시뮬레이터 build/run 검증

### Phase 3 — PhotoDetail + 메모

- `Camork/Gallery/PhotoDetailView.swift` — 단일 사진 풀스크린 (Zoomable scrollview), 메모 편집(`TextEditor` sheet)
- `Camork/Sessions/PhotoMemoEditor.swift` — 메모 저장 로직 (MediaStorage 위임)
- 단위 테스트: 메모 update API (save + reload)
- 시뮬레이터 검증: thumb 탭 → 풀스크린 진입 → 메모 입력 → 닫기 → 재진입 시 메모 유지

### Phase 4 — 통합 회귀 + 실기기 manual + 완료 보고서

- `xcodebuild clean + test` 전체 회귀 (모든 단위 테스트 통과 + 0 failures)
- **실기기 manual checklist 실행** (Section 10 참조)
- `docs/superpowers/reports/2026-05-19-plan-B-storage-camera-complete.md` 작성
- Plan C 인계 항목 정리 (Section 11)

---

## 3. 데이터 모델 (High-level relational schema, ADR에서 정식화)

### 3.1 Schema 가설 (v1 Core)

```sql
-- migration v1
CREATE TABLE Session (
  id TEXT PRIMARY KEY,                  -- UUID 문자열
  name TEXT NOT NULL,                   -- 자동 또는 사용자 변경
  note TEXT,
  createdAt INTEGER NOT NULL,           -- Unix epoch (seconds)
  endedAt INTEGER,                      -- NULL = 진행 중
  -- 세션 첫 사진의 LocationSnapshot (embed)
  firstLat REAL,
  firstLon REAL,
  firstHorizontalAccuracy REAL,
  firstPlaceName TEXT,
  -- v1.1+: folderId TEXT REFERENCES Folder(id) ON DELETE SET NULL
  -- v1 Core에서는 folderId 컬럼 미생성, v1.1 migration v2에서 ALTER TABLE
  deletedAt INTEGER                     -- 휴지통 (Plan C)
);

CREATE TABLE Photo (
  id TEXT PRIMARY KEY,                  -- UUID 문자열 = fileName 기반
  sessionId TEXT NOT NULL REFERENCES Session(id) ON DELETE CASCADE,
  fileName TEXT NOT NULL,               -- "<UUID>.heic" (relative)
  thumbnailFileName TEXT,               -- "<UUID>.jpg" (relative, 캐시)
  kind TEXT NOT NULL,                   -- 'photo' | 'video' (v1 Core: 'photo'만)
  capturedAt INTEGER NOT NULL,
  -- LocationSnapshot (embed)
  lat REAL,
  lon REAL,
  horizontalAccuracy REAL,
  placeName TEXT,
  -- EXIF는 JSON blob (v1.1+ 검색에서 EXIF 조건은 비현실적이라 인덱스 불필요)
  exifJson TEXT,
  note TEXT,
  deletedAt INTEGER
);

CREATE INDEX idx_Photo_sessionId ON Photo(sessionId);
CREATE INDEX idx_Photo_capturedAt ON Photo(capturedAt DESC);
CREATE INDEX idx_Session_createdAt ON Session(createdAt DESC);
```

**Folder 테이블은 v1 Core 미생성** — v1.1에서 `migration v2`로 `CREATE TABLE Folder + ALTER TABLE Session ADD COLUMN folderId`.

### 3.2 Swift 모델 가설

```swift
struct Session: Identifiable, Codable, FetchableRecord, PersistableRecord, Sendable {
    let id: UUID
    var name: String
    var note: String?
    var createdAt: Date
    var endedAt: Date?
    var firstLocation: LocationSnapshot?
    var deletedAt: Date?
}

struct Photo: Identifiable, Codable, FetchableRecord, PersistableRecord, Sendable {
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
}

struct LocationSnapshot: Codable, Sendable, Equatable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let placeName: String?
}

enum MediaKind: String, Codable, Sendable {
    case photo
    // case video // v1.2
}

struct ExifData: Codable, Sendable {
    let iso: Int?
    let shutterSpeed: Double?
    let aperture: Double?
    let focalLength: Double?
    let deviceModel: String?
    let osVersion: String?
}
```

### 3.3 PhotoCapturePayload (AVFoundation callback → actor 경계)

```swift
/// Sendable payload — AVCapturePhoto에서 추출, actor로 안전 hop.
struct PhotoCapturePayload: Sendable {
    let id: UUID
    let imageData: Data                  // HEIC encoded
    let capturedAt: Date
    let location: LocationSnapshot?
    let exif: ExifData?
}
```

---

## 4. 동시성 정책 요약 (결정 #3 + ADR 인계)

| 영역 | 정책 |
|---|---|
| `actor MediaStorage` | DB write + 파일 IO 직렬화. GRDB `DatabaseWriter` + 파일 시스템 소유. |
| `actor SessionManager` | 자동 묶기 + lazy flag. persist via MediaStorage `await` 호출. |
| `@MainActor` | View / ViewModel / UI state만. Photo/Session struct + Storage protocol 제외. |
| AVFoundation queue | dedicated `DispatchQueue` (nonisolated). callback에서 `AVCapturePhoto` 직접 hop 금지 → `PhotoCapturePayload`(Sendable) 변환. |
| Cross-actor | `await` 직접 호출만. Combine/AsyncStream UI 구독에만. |
| Reentrancy | `await` 전후 mutation 안 나누는 구조 우선. Lock은 최후 수단. |
| 의존성 주입 | Singleton 금지. App root container → Environment로 전파. |

---

## 5. Session 자동 묶기 정책 (6 edge case, 단위 테스트 대상)

### 5.1 자동 분리 규칙

촬영이 발생하면 다음 순서로 판단:

1. `pendingManualSessionStart == true` → **새 세션 생성**, 플래그 clear (manual flag 최우선)
2. 직전 세션 없음 (첫 촬영) → 새 세션 생성
3. 직전 세션의 마지막 사진 위치 + 현재 위치 모두 있음 + `horizontalAccuracy ≤ 30m`:
   - 거리 ≥ 50m → 새 세션
4. 직전 사진 `capturedAt`으로부터 30분 이상 경과 → 새 세션
5. 외 모두 → 직전 세션에 이어쓰기

### 5.2 6 Edge case 정책 (모두 테스트 가능)

| Case | 정책 | 테스트 시나리오 |
|---|---|---|
| **a. GPS latency** | best-effort. 촬영 시 가용 latest known location 사용. 없으면 `location: nil`. 사후 보강 X. | `LocationService.latestKnown == nil` 상태에서 촬영 → `Photo.location == nil`로 저장. |
| **b. 위치 권한 거부** | 시간 규칙만 (30분 무촬영). | `PermissionsService.location == .denied` → 거리 규칙 skip, 시간 규칙만 평가. |
| **c. 첫 촬영** | 새 세션 자동 생성, `createdAt = now`. | 빈 DB에서 첫 촬영 → 새 `Session` insert 후 `Photo` insert. |
| **d. "새 현장" 누르고 안 찍음** | `pendingManualSessionStart` 플래그만 set (in-memory). 빈 세션 영속 X. | flag set → 종료 → flag drop. DB에 빈 Session 없음. |
| **e. background → 30분+ 복귀 → 촬영** | 시간 규칙 자연 적용. 새 세션 분리. | mock time travel +31min → 촬영 → 새 세션. |
| **f. "새 현장" 여러 번 + GPS/30분 규칙도 만족** | manual flag가 우선. 단 1개의 새 세션만. | flag set 3회 + 50m 이동 + 31min 경과 → 새 세션 1개만 생성, flag clear. |

### 5.3 SessionManager API

```swift
actor SessionManager {
    private var pendingManualSessionStart: Bool = false
    private let storage: MediaStorage
    private let locationService: LocationService

    func markPendingNewSession() {
        pendingManualSessionStart = true   // idempotent
    }

    func assignToNewOrCurrentSession(
        photoId: UUID,
        capturedAt: Date,
        location: LocationSnapshot?
    ) async throws -> UUID {  // returns sessionId
        // 위 5.1 로직 적용
    }
}
```

---

## 6. AVFoundation TDD 정책 요약 (결정 #2)

- AVFoundation 레이어는 thin wrapper.
- **단위 테스트 대상**: metadata builder, file naming (UUID + extension), session assignment, permission state mapping, error mapping.
- **단위 테스트 미대상 (실기기 manual)**: AVCaptureSession 시작/정지 lifecycle, 실제 캡처 파일 생성, 권한 거부 UX 흐름, 백그라운드 시 세션 정지.
- **Mock AVCaptureSession protocol abstraction 미도입.** lifecycle 분기가 복잡해지는 시점(v1.2 동영상 / Plan E 백그라운드 가림막)에 재검토.
- callback의 `AVCapturePhoto`를 `PhotoCapturePayload`(Sendable)로 변환 후 actor hop. non-Sendable 객체 hop은 빌드 단계에서 Swift concurrency 검증.

---

## 7. UX 흐름

### 7.1 카메라 화면 (Phase 2c)

상단: 좌측 잠금 아이콘 placeholder (Plan E), 중앙 "새 현장" 칩(`Label("button_new_site", systemImage: "plus.circle")`), 우측 갤러리 아이콘 placeholder (Plan C).

중앙: `AVCaptureVideoPreviewLayer` 뷰파인더.

하단: 좌하단 직전 사진 thumb (50x50, 둥근 모서리 — 탭 시 PhotoDetail 진입), 중앙 셔터 (`Button`, 큰 흰 원), 우하단 카메라 전환 (`Button`, `arrow.triangle.2.circlepath.camera`).

권한 거부 시: 뷰파인더 자리에 `ContentUnavailableView` — 제목/설명 + "설정 열기" 버튼(URL `UIApplication.openSettingsURLString` → `UIApplication.shared.open`).

### 7.2 PhotoDetail (Phase 3)

- 풀스크린 모달 (sheet, `presentationDetents([.large])` 또는 `fullScreenCover`).
- 상단 좌측 닫기 (X), 우측 메모 편집 버튼.
- 가운데 사진 (`Image` + `ZoomableScrollView` — 핀치 줌, 더블탭 줌, 팬).
- 하단 메타 정보 (시간 · 지역 · 사진 수 — 작게).
- 메모 편집: `sheet`에서 `TextEditor` (자동 포커스, 키보드 dismiss는 우상단 "완료" 버튼). 저장은 sheet dismiss 시 `await mediaStorage.updatePhotoNote(...)`.

### 7.3 새 현장 칩 UX

- 탭 시: `await sessionManager.markPendingNewSession()` (idempotent).
- 시각 피드백: 칩이 잠시 강조 색 (오렌지 액센트) 으로 깜빡임, 햅틱 light tap.
- 화면 다른 변화 없음 (다음 촬영 시 새 세션 생성됨).
- 칩 상태 유지: `@State` 또는 actor에서 `isPendingNewSession()` async getter — UI에 작은 dot indicator 표시 가능.

---

## 8. 테스트 전략

### 8.1 단위 테스트 (Swift Testing, in-memory DB)

- **SessionManager**: 6 edge case (a~f), GPS accuracy 25/30/35m 경계, 시간 29/30/31min 경계.
- **MediaStorage**: 파일 저장 + DB insert 트랜잭션, isExcludedFromBackup 플래그, 동시 쓰기 순서.
- **Database/Migration**: migration v1 schema 정합, 마이그레이션 idempotent.
- **PermissionsService**: 권한 상태 매핑 (granted/denied/notDetermined/restricted), Info.plist 키 일치.
- **MediaCapture**: PhotoCapturePayload 변환, EXIF 임베드, file naming UUID 형식.
- **PhotoMemoEditor**: 메모 update + reload, nil 처리.
- **LocationService**: latest known location 노출, 권한 없을 때 nil.

### 8.2 통합 테스트 (시뮬레이터)

- 카메라 권한 거부 → 권한 안내 화면 보임 + 설정 deeplink 동작.
- 시뮬레이터 dummy camera에서 셔터 → DB insert → thumb 갱신.
- thumb 탭 → PhotoDetail 진입 → 메모 입력 → 저장 → 재진입 → 메모 유지.

### 8.3 실기기 manual checklist (Section 10)

---

## 9. 에러 처리

| 상황 | 동작 |
|---|---|
| 카메라 권한 거부 | 뷰파인더 자리에 권한 안내 + 설정 deeplink |
| 위치 권한 거부 | `location: nil`로 저장, 세션 분리는 시간 규칙만 |
| 마이크 권한 (v1 Core 미사용) | 무시 |
| 저장공간 부족 | 촬영 전 경고 (Plan E에서 정밀화), 촬영 중 실패 시 에러 토스트 |
| AVCaptureSession 초기화 실패 | 재시도 1회 → 실패 시 에러 화면 + 다시시도 버튼 |
| GRDB write 실패 | 파일은 임시 폴더에서 cleanup, 사용자에게 에러 토스트, 로그 |
| DB migration 실패 | 사용자 안내 "데이터 손상, 앱 재설치 권장" — v1 Core 출시 전 절대 발생 X |
| 백그라운드 진입 | `AVCaptureSession.stopRunning()` 호출. (가림막은 Plan E) |
| PhotoDetail 사진 파일 누락 | `ContentUnavailableView` "사진을 찾을 수 없음" 표시 |

---

## 10. 실기기 manual checklist

Plan B 완료 보고서에 다음 결과 첨부 (Phase 4):

### 10.1 카메라 lifecycle
- [ ] 앱 첫 시작 → 카메라 권한 요청 prompt 뜸
- [ ] 권한 허용 → 뷰파인더 정상 표시
- [ ] 권한 거부 → 안내 화면 + "설정 열기" 버튼 → 설정 앱에서 권한 토글
- [ ] 셔터 탭 → 짧은 햅틱 + thumb 갱신 + 셔터 reset
- [ ] 카메라 전환 (전면/후면) 동작
- [ ] 백그라운드 진입 시 카메라 세션 정지 (배터리 사용량 떨어짐)
- [ ] 백그라운드 → 복귀 시 카메라 자동 재시작

### 10.2 저장 검증
- [ ] 촬영 후 `~/Library/Application Support/Camork/Media/<UUID>.heic` 파일 존재 확인 (Files 앱 또는 Xcode 디바이스 logs)
- [ ] DB 파일 (`camork.sqlite`) 생성됨
- [ ] iCloud 백업에서 제외됨 (`isExcludedFromBackup` 플래그 검증 — 어렵다면 Xcode Organizer)
- [ ] 위치 권한 허용 시 사진 위치 메타가 저장됨 (Photo.location ≠ nil)
- [ ] 위치 권한 거부 시 위치 메타 없이 저장 (Photo.location == nil)

### 10.3 세션 자동 묶기
- [ ] 첫 촬영 시 새 세션 생성 (DB 확인)
- [ ] 같은 자리 연속 촬영 → 같은 세션에 누적
- [ ] 30분 이상 무촬영 후 촬영 → 새 세션 분리
- [ ] (가능하면) 다른 장소 이동 후 촬영 → 새 세션 분리
- [ ] "새 현장" 칩 탭 → 다음 촬영이 새 세션 (앱 종료 전)
- [ ] "새 현장" 칩 탭 후 촬영 없이 앱 종료 → 재시작 시 빈 세션 없음

### 10.4 PhotoDetail + 메모
- [ ] thumb 탭 → 풀스크린 진입
- [ ] 핀치 줌 / 더블탭 줌 / 팬 동작
- [ ] 메모 편집 → 닫기 → 재진입 시 메모 유지
- [ ] 빈 메모도 저장 (nil로)

### 10.5 비주얼 / 접근성
- [ ] 다크 모드 / 라이트 모드 모두 정상
- [ ] Dynamic Type AX5에서 안 깨짐
- [ ] VoiceOver: 셔터/카메라 전환/새 현장 칩 라벨 명확
- [ ] 한국어 / 영어 모두 잘림 없음

---

## 11. Plan C 인계 항목

### 11.1 결정 필요 (Plan C 진입 시점)

1. **갤러리 메인 화면 layout** — 세션 카드 리스트 정렬, 시간 필터 칩 위치, 검색바 노출 시점.
2. **세션 카드 디자인** — 사진 미리보기 그리드 (4장? 1장? 콜라주?), 메타 텍스트 위치.
3. **시간 필터 칩** — 전체 / 7일 / 이번 달 외 추가 필터?
4. **지도 토글 (Plan C? v1.2?)** — Plan C에 포함 vs Plan D 이후로 미룸.
5. **세션 진입 후 UI** — 사진 그리드 (정사각형) vs 시간순 리스트?
6. **세션 이름 편집** — 인라인 vs sheet?

### 11.2 인프라 (Plan B에서 박아둔 것)

- `actor MediaStorage` API에 `fetchSessions(filter:)`, `fetchPhotos(sessionId:)` 추가 (Plan C에서 구현, 인터페이스는 Plan B에 stub)
- 휴지통 (`deletedAt` 컬럼)은 schema에 미리 있음 — Plan C에서 UI 노출

### 11.3 미해결 (출시 전)

- AccentColor 정확 hex (Plan E)
- App Icon (Plan E)
- 영문 카피 정밀화 (Plan E)
- Swift 6 전환 (Plan B Storage ADR 완료 후 별도 결정)

---

## 12. 오픈 이슈 (writing-plans 단계에서 결정)

- GRDB 정확 버전 (latest stable vs LTS)
- HEIC 압축 품질 (default vs 사용자 설정)
- thumbnail 크기 (정사각형 200pt? 또는 화면 비율?)
- PhotoDetail의 zoom max scale (3x? 5x?)
- "새 현장" 칩 햅틱 강도 (light / medium)
- 메모 편집 sheet의 detents (medium만 / large만 / 둘 다?)
- ExifData에 어떤 필드를 EXIF blob에 포함할지 (필수 vs 옵션)
- DB write 실패 시 retry 정책 (즉시 1회 / 백오프?)

---

## 다음 단계

1. **spec review loop** — momus에게 본 spec을 검토 받음. Critical/Should-fix 반영 후 재검토.
2. **사용자 review** — 통과 후 사용자가 본 spec을 직접 읽고 변경 요청 / 승인.
3. **승인 시** — `superpowers:writing-plans` 스킬로 Plan B 구현 계획 작성 (Phase 1.0 ADR이 첫 task).
