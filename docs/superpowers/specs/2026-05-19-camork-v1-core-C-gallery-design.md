# Plan C — Gallery + Share v1 (v1 Core) Design Spec

- **작성일:** 2026-05-19
- **상태:** 초안 (사용자 + critique 검토 대기)
- **참조:**
  - 마스터 spec: `docs/superpowers/specs/2026-05-19-camork-rebuild-design.md` §4.3, §4.4, §5.6, §9, §12
  - Plan B spec: `docs/superpowers/specs/2026-05-19-camork-v1-core-B-storage-camera-design.md` §11.1, §13, §14
  - Plan B 보고서: `docs/superpowers/reports/2026-05-19-plan-B-storage-camera-complete.md` §6
  - Phase 1.0 ADR: `docs/superpowers/adrs/2026-05-19-storage-and-concurrency.md`
- **결정 기준 (2026-05-19):** B1 (ShareComposer-lite) / on-demand persistent cache / D2 (Trash viewer Plan E) / 4+N preview / 정사각형 grid / 세션명·메모 sheet 편집

---

## 1. Goal / Scope / 완료 기준

### 1.1 Goal

Plan B의 capture-save 파이프라인 위에 갤러리 + 안전한 공유 + 메모 UI를 얹는다. master spec §4.3/§4.4의 v1 Core scope를 그대로 충족 — 검색/시간 필터/지도/폴더는 v1.1로 분리하고, share는 lite + sanitized temp copy 경로로 v1 Core에 포함.

### 1.2 Plan C 포함 (v1 Core 완성)

- **Gallery 탭** — `RootTabView`의 "Sites" 슬롯에 실제 `GalleryScreen`. 세션 카드 리스트, 시간순 역방향.
- **세션 카드** — 4-photo preview + +N 배지, 세션명·시간·위치명·사진 수, 우측 공유/더보기 (master §4.3 그대로).
- **세션 진입 화면** — 정사각형 photo grid + 세션명 편집 + 세션 메모 편집 (둘 다 sheet).
- **PhotoDetailView 재사용** — Plan B 산출 (`Camork/Gallery/PhotoDetailView`) init 시그너처 unchanged.
- **Thumbnail cache pipeline** — on-demand 영속 캐시 (`Library/Caches/Camork/Thumbnails/<UUID>.jpg`), 가시/근접 항목만 생성, in-flight coalesce, bounded concurrency, off-main 디코딩.
- **Share v1 — ShareComposer-lite** — `tmp/Camork/Share/<UUID>/` 임시 사본 + EXIF location strip (위치 토글 OFF 시) + 자동 텍스트 + `UIActivityViewController` 위임 + cleanup.
- **Query-level Trash 필터** — 모든 `fetchSessions` / `fetchPhotos`에서 `deletedAt IS NULL`.
- **MediaStorage 신규 public API** — `fetchSessions(sortedBy:)`, `fetchPhotos(sessionId:)`, `loadThumbnailData(for:)`, `updateSessionName(...)`, `updateSessionNote(...)`.

### 1.3 Plan C 제외 (v1.1 또는 Plan D/E)

- 검색바 / 시간 필터 칩 / 지도 토글 / 폴더 / FTS5 검색 → **v1.1**
- Trash viewer UI (휴지통 목록 + 복원 + 영구 삭제) → **Plan E** (Settings 일괄)
- delete UI 자체 노출 → Plan E (viewer 없으면 stranded items 위험)
- Share v2 — 사전 텍스트 편집 미리보기 화면, Camork 측 channel ranking/preselect, custom share UI → **Plan D**
- 동영상 → **v1.2** (`MediaKind.video` 추가)

### 1.4 완료 기준 (v1 Core 출시 후보)

- xcodebuild test SUCCEEDED — Plan B 누적 90건 + Plan C 신규 ~30+건 통과.
- 시뮬레이터 manual: seeded capture → 갤러리 → 세션 카드 → 진입 → 사진 그리드 → photo detail → 메모 → 닫기 → 재진입 시 메모 유지.
- 실기기 manual: §10 카테고리 전부 (lifecycle/저장/세션/detail/share/visual).
- 성능 §12: 갤러리 첫 화면 <0.3s (warm cache 기준 500 sessions / 5,000 photos), 60fps 스크롤, 메모리 < 200MB 카메라 활성 시.

---

## 2. Phase 분할

### Phase 1 — 갤러리 데이터 API (TDD, 단위 테스트)
- 1.1 — `MediaStorage.fetchSessions(sortedBy:) async throws -> [Session]` + `fetchPhotos(sessionId:) async throws -> [Photo]` + query-level `deletedAt IS NULL`
- 1.2 — `MediaStorage.updateSessionName(...)` + `updateSessionNote(...)` + `MediaStorage.Error.sessionNotFound` (PhotoMemoEditor.notFound 패턴 mirror)
- 1.3 — `SessionPreview` 계산 (세션의 가장 최근 4개 사진 + 총 사진 수). DB 쿼리로 한 번에 (N+1 회피)

### Phase 2 — Thumbnail cache pipeline
- 2.1 — `FileOps`에 `readThumb(fileName:)`, `writeThumb(fileName:data:)`, `removeThumb(fileName:)` 확장 + `MediaFileSystem` 구현 (`Library/Caches/Camork/Thumbnails/` 사용 — iOS가 backup에서 자동 제외, file protection은 디렉토리 + writeThumb 양쪽에 명시 적용)
- 2.2 — `ThumbnailGenerator` actor (또는 `MediaStorage` 내 free function) — UIImage 디코딩 + 비율 유지 resize + JPEG 인코딩. Off-main thread.
- 2.3 — `MediaStorage.loadThumbnailData(for: Photo) async throws -> Data` — cache hit 즉시 반환, miss 시 원본 디코딩 + thumbnail 생성 + cache write + 반환
- 2.4 — `ThumbnailCoordinator` actor — in-flight 요청 coalesce + bounded concurrency (max 4 동시)
- 2.5 — Reaper 확장 — `runReaper`가 `Thumbnails/`도 orphan 정리 (DB Photo row 없는 thumbnail 제거)

### Phase 3 — Gallery UI
- 3.1 — `GalleryScreen` (`@EnvironmentObject deps`) — 세션 카드 LazyVStack
- 3.2 — `SessionCardView` — 4-photo preview Grid + +N + 메타 행 + 공유/더보기 (단 더보기는 placeholder, delete UI 없음)
- 3.3 — `ThumbnailView` SwiftUI 컴포넌트 — 고정 크기 placeholder + Task로 `loadThumbnailData(for:)` 호출 + cancel on view disappear
- 3.4 — `SessionDetailScreen` — 정사각형 photo grid + 헤더(세션명·메타) + 세션명/메모 편집 sheet
- 3.5 — `SessionNameEditor` / `SessionNoteEditor` (PhotoMemoEditor 패턴 mirror)
- 3.6 — `RootTabView` — `GalleryPlaceholderView` → `GalleryScreen` 교체

### Phase 4 — Share v1 lite
- 4.1 — `ShareSanitizer` (struct + static pure) — `Data` + 위치 strip 옵션 → Data. `kCGImagePropertyGPSDictionary` / GPS 메타를 명시 제거하고 orientation / color profile / DateTimeOriginal은 보존 (§5.2 상세)
- 4.2 — `SharePreparer` (actor) — `tmp/Camork/Share/<UUID>/`에 sanitized 사본 + 자동 텍스트 생성 ("[세션명] · 시간 · 지역 — 사진 N장")
- 4.3 — `ShareSheetController` (UIViewControllerRepresentable) wrap `UIActivityViewController` + completion callback
- 4.4 — `ShareEntryButton` SwiftUI — 위치/시간 토글 + "공유하기" tap → SharePreparer → ShareSheetController
- 4.5 — `tmp/Camork/Share/` cleanup — 앱 시작 시 (Bootstrap) + 각 share completion 시

### Phase 5 — 통합 회귀 + manual + 보고서
- 5.1 — clean build + 전체 회귀
- 5.2 — 실기기 manual checklist (§10)
- 5.3 — Plan C 완료 보고서 + Plan D 인계

---

## 3. 데이터 모델

### 3.1 Schema 변경

**v1 Core schema는 변경 없음** — Plan B의 Photo/Session 테이블 + `deletedAt` + `thumbnailFileName` 컬럼이 이미 충분.

### 3.2 신규 MediaStorage public API (Plan B 단계에는 stub 없음, Plan C가 신규 도입)

```swift
extension MediaStorage {
    enum Error: Swift.Error, Sendable, Equatable {
        case invalidFileName        // (기존 Plan B)
        case sessionNotFound        // 신규 — Plan C updateSessionName/Note
    }

    /// 시간순 역방향 + deletedAt IS NULL.
    func fetchSessions(sortedBy: SessionSort = .createdAtDesc) async throws -> [Session]

    /// 세션 내 photo 전체. deletedAt IS NULL.
    func fetchPhotos(sessionId: UUID) async throws -> [Photo]

    /// 세션 카드의 "4-photo preview + +N" 표시용. 사진 수 + 가장 최근 4 photo를 한 번에.
    func fetchSessionPreview(sessionId: UUID) async throws -> SessionPreview

    /// 모든 세션 + 각 세션의 preview를 한꺼번에. 구현은 1 SQL (window function)
    /// 또는 2 batched SQL (sessions + 가시/최근 세션의 preview photos)이 허용 —
    /// invariant는 **per-session N+1 쿼리 금지**.
    func fetchSessionsWithPreview(sortedBy: SessionSort = .createdAtDesc) async throws -> [SessionWithPreview]

    /// thumbnail cache. miss 시 원본 디코딩 + 생성 + cache write. canonical fileName 검증 동일.
    func loadThumbnailData(for photo: Photo) async throws -> Data

    /// 세션명 편집. 빈 문자열은 거부 — sessionNotFound 분기 mirror로 throws.
    func updateSessionName(sessionId: UUID, name: String) async throws

    func updateSessionNote(sessionId: UUID, note: String?) async throws
}

enum SessionSort: Sendable {
    case createdAtDesc  // v1 Core 기본
}

struct SessionPreview: Sendable {
    let sessionId: UUID
    let totalPhotoCount: Int
    /// capturedAt DESC 기준 최대 4개. 4 미만이면 그대로.
    let previewPhotos: [Photo]
}

struct SessionWithPreview: Sendable {
    let session: Session
    let preview: SessionPreview
}
```

### 3.3 SessionNameEditor / SessionNoteEditor (PhotoMemoEditor 패턴 mirror)

```swift
struct SessionNameEditor: Sendable {
    enum Error: Swift.Error, Sendable, Equatable {
        case notFound
        case emptyName   // 빈 문자열은 도메인 invariant 위반
    }
    let mediaStorage: MediaStorage
    func update(sessionId: UUID, name: String) async throws
}

struct SessionNoteEditor: Sendable {
    enum Error: Swift.Error, Sendable, Equatable {
        case notFound
    }
    let mediaStorage: MediaStorage
    func update(sessionId: UUID, note: String?) async throws
}
```

---

## 4. Thumbnail cache pipeline 설계 (Phase 2 핵심)

### 4.1 위치 + 명명

- **경로**: `Library/Caches/Camork/Thumbnails/<photo.id.uuidString>.jpg`
  - `Library/Caches/`를 사용 — iOS가 공간 부족 시 자동 정리 (재생성 가능 자원).
  - `Photo.thumbnailFileName` 컬럼은 사용하지 않음 — UUID-based 명명만으로 충분, 별도 컬럼 관리 부담 회피. (Plan B의 thumbnailFileName 컬럼은 v1.2+ 별도 thumb 종류가 필요해질 때 활용)
- **포맷**: JPEG quality 0.8 (HEIC보다 호환 + 크기 적당).
- **크기**: 짧은 변 기준 400pt × scale (Retina 3x = 1200px). 큰 변은 비율 유지.

### 4.2 흐름

```
loadThumbnailData(for: photo) async throws -> Data
├─ canonical fileName 검증 (Plan B loadPhotoData와 동일)
├─ ThumbnailCoordinator에게 위임 (in-flight coalesce + bounded concurrency)
│   ├─ cache hit ("<UUID>.jpg" 존재) → fs.readThumb(...) 반환
│   └─ cache miss
│       ├─ Plan B fs.readFinal(...) → 원본 HEIC Data
│       ├─ UIImage(data:) → ImageIO downscale (off-main)
│       ├─ JPEG encode (0.8)
│       ├─ fs.writeThumb(<UUID>.jpg, jpegData)
│       └─ jpegData 반환
└─ Error path: 원본 디코딩 실패 시 throw (호출자 = placeholder fallback)
```

### 4.3 ThumbnailCoordinator 책임

```swift
actor ThumbnailCoordinator {
    private var inFlight: [UUID: Task<Data, Swift.Error>] = [:]
    private let concurrencyLimit = 4
    private var activeCount = 0

    func loadThumbnailData(for photo: Photo, source: MediaStorage) async throws -> Data {
        // 1. inFlight에 있으면 같은 Task 결과 await (coalesce)
        // 2. activeCount >= limit이면 await semaphore-like 패턴
        // 3. cache hit 빠른 path
        // 4. miss → 생성 task spawn, inFlight[photoId] = task
        // 5. 완료 시 inFlight 제거
    }
}
```

Bounded concurrency는 `AsyncSemaphore`-pattern (Swift 표준은 없으므로 actor counter)로. 4 동시 디코딩이 60fps 스크롤에 충분.

### 4.4 Acceptance criteria (성능 §12 충족)

- **Cold cache** (앱 첫 시작 + 캐시 비어 있음):
  - 첫 화면 전환에 placeholder 100% 표시 허용 (skeleton/실루엣).
  - 가시 항목은 0.5초 이내 thumbnail 도착.
  - 사용자 스크롤 시 항목이 viewport에 들어오는 순간 generation 시작.
- **Warm cache** (이전에 본 화면 재진입):
  - **<0.3s 첫 화면** — master §12 기준 충족.
  - 60fps 스크롤 (500 sessions / 5,000 photos).
- **UI 규칙**:
  - list/grid에서 **raw HEIC 디코딩 금지** — 항상 `loadThumbnailData(for:)` 경유.
  - `ThumbnailView`는 placeholder를 즉시 렌더링 + Task로 비동기 로딩.
  - View가 viewport 밖으로 나가면 Task cancel (생성 작업 중단).

### 4.5 Eviction / 공간 관리

- `Library/Caches/`는 iOS 자동 관리 — 따로 LRU 구현 없음.
- `runReaper`가 DB Photo row 없는 thumbnail 파일을 정리 (`fs.enumerateThumb` + DB filename set 비교).
- 디스크 가득 → `writeThumb` 실패 → 호출자는 raw 디코딩 fallback 없이 placeholder 유지 (다음 시도 재생성).

### 4.6 Backup / Data Protection

- `Library/Caches/`는 iOS 시스템적으로 iCloud/iTunes backup에서 자동 제외 — `isExcludedFromBackup` flag를 따로 설정할 필요 없음.
- 하지만 Data Protection은 자동 적용되지 않으므로 thumbnail 파일 작성 시 **`FileProtectionType.completeUntilFirstUserAuthentication`** 명시 적용 (Plan B의 Media/와 동일 정책 — 부팅 후 첫 잠금 해제까지 디스크 암호화 유지). thumbnail도 사용자 콘텐츠 파생물이라 민감.
- `FileOps.writeThumb(...)`는 `data.write(to:options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])`로 작성.
- 디렉토리 자체에도 `setAttributes(.protectionKey: .completeUntilFirstUserAuthentication)` 적용 (`MediaFileSystem.bootstrap`이 Media/에 적용하는 패턴 mirror).

---

## 5. Share v1 lite 설계 (Phase 4 핵심)

### 5.1 흐름

```
사용자 진입점
├─ Session card 우측 공유 아이콘 — 세션 전체 photos 공유
└─ PhotoDetailView 공유 버튼 (Plan B의 topBar에 추가) — 단일 photo 공유
        ↓
ShareEntryButton (SwiftUI sheet 또는 alert)
├─ 위치 토글 (기본 ON, 사진에 location 메타 있을 때만 표시)
├─ 시간 토글 (기본 ON)
└─ "공유하기" tap
        ↓
SharePreparer actor
├─ 1. tmp/Camork/Share/<UUID>/ 디렉토리 생성
├─ 2. 각 photo에 대해:
│   ├─ fs.readFinal(photo.fileName) → 원본 HEIC Data
│   ├─ ShareSanitizer.sanitize(data:, stripLocation:) → sanitized Data (ImageIO)
│   └─ tmp/.../photo-N.heic 작성
├─ 3. 자동 텍스트 생성 — "[세션명] · YYYY-MM-DD HH:mm · 위치명 — 사진 N장"
│   ├─ 위치 토글 OFF → "위치명 · " 제거
│   └─ 시간 토글 OFF → "· YYYY-MM-DD HH:mm" 제거
└─ 4. ShareSheetController(activities: [URLs, text]) 반환
        ↓
ShareSheetController (UIViewControllerRepresentable)
├─ UIActivityViewController
├─ 사용자가 채널 선택 / 취소
└─ completionWithItemsHandler
        ↓
        cleanup
        ├─ completion 시 tmp/Camork/Share/<UUID>/ 삭제
        └─ 앱 시작 시 (Bootstrap) — orphan tmp 디렉토리 일괄 정리 (24시간 이상)
```

### 5.2 ShareSanitizer (static pure)

```swift
struct ShareSanitizer: Sendable {
    enum Error: Swift.Error, Sendable {
        case decodeFailed
        case encodeFailed
    }

    /// stripLocation true면 EXIF/IPTC/XMP의 GPS 키 전부 제거.
    /// HEIC → HEIC 재인코딩 (ImageIO + AVFoundation Codec).
    static func sanitize(
        data: Data,
        stripLocation: Bool
    ) throws -> Data
}
```

- **GPS 제거 명시**: `kCGImagePropertyGPSDictionary` 전체 제거. EXIF/XMP 어느 위치에 들어 있어도 stripping (단순 `kCGImageMetadataShouldExcludeXMP` 한 flag로는 EXIF GPS가 남을 수 있음). 검증은 sanitize 후 `CGImageSourceCopyPropertiesAtIndex`로 GPS 키 부재 확인.
- **유지해야 할 메타**:
  - `kCGImagePropertyOrientation` — 회전 정보 (없으면 가로/세로 잘못 표시).
  - ICC color profile (`kCGImagePropertyColorModel` 등) — 색역.
  - `kCGImagePropertyExifDateTimeOriginal` — 촬영 시간 (사용자 의도). 시간 토글은 자동 텍스트 영향만, EXIF DateTimeOriginal은 의도적으로 보존.
- **단위 테스트 항목**:
  - location ON: GPS dict 유지.
  - location OFF: GPS dict 부재 (EXIF + XMP 양쪽 검증).
  - orientation 메타 보존 (90도 회전 입력 → 재인코딩 후 동일 orientation 키).
  - DateTimeOriginal 보존 (location 토글과 무관).
  - color profile 보존 (입력 ICC profile == 출력).

### 5.3 SharePreparer

```swift
actor SharePreparer {
    private let fs: any FileOps
    private let mediaStorage: MediaStorage

    func prepare(
        photos: [Photo],
        session: Session,
        includeLocation: Bool,
        includeTime: Bool
    ) async throws -> ShareBundle

    /// 앱 시작 시 (Bootstrap) — 24h 이상 된 tmp/Camork/Share/* 디렉토리 정리.
    func cleanupExpired() async
}

struct ShareBundle: Sendable {
    let fileURLs: [URL]   // tmp/Camork/Share/<UUID>/photo-N.heic
    let autoText: String
}
```

### 5.4 자동 텍스트 형식 (master §4.4 그대로)

```
[세션명] · 2026-05-19 14:30 · 도산공원 — 사진 5장
```

- 위치 OFF → `[세션명] · 2026-05-19 14:30 — 사진 5장`
- 시간 OFF → `[세션명] · 도산공원 — 사진 5장`
- 둘 다 OFF → `[세션명] — 사진 5장`

### 5.5 cleanup 시점

- **share completion** — `UIActivityViewController` completion handler에서 `try? fs.removeItem(at: bundle.tempDir)`.
- **앱 시작 시 (Bootstrap)** — `DependencyContainer.init`에서 `SharePreparer.cleanupExpired()` 호출 (24h 경과 orphan).
- master §5.5: 공유 임시파일 수명 24h가 spec 기준.

### 5.6 boundary (Plan C vs Plan D)

| 항목 | Plan C lite | Plan D 풀스펙 |
|---|---|---|
| temp sanitized 사본 | ✅ | (그대로 재사용) |
| EXIF location stripping (toggle) | ✅ | (그대로 재사용) |
| 자동 텍스트 생성 | ✅ 단순 형식 | ✅ 편집 가능한 사전 미리보기 화면 |
| UIActivityViewController 위임 | ✅ | (그대로 재사용) |
| cleanup | ✅ | (그대로 재사용) |
| 위치/시간 토글 | ✅ alert/sheet 형태 | ✅ 풀스펙 ShareComposer 화면에 통합 |
| Camork 측 channel ranking | ❌ | ✅ |
| Camork 측 channel preselect / custom share UI | ❌ | ✅ |
| 사전 텍스트 편집 미리보기 화면 | ❌ | ✅ |
| iOS share sheet 자동 채널 노출 (KakaoTalk/Telegram 등) | ✅ (시스템 동작) | ✅ |

---

## 6. Trash query filter (Phase 1)

### 6.1 적용 규칙

- 모든 `fetchSessions*` / `fetchPhotos*` / `fetchSessionPreview` 쿼리에 `WHERE deletedAt IS NULL`.
- 기존 `fetchPhoto(id:)`도 동일하게 `deletedAt IS NULL` 강제 — 호출자에게 검사 책임 분산 금지 (caller가 까먹으면 deleted item이 silently 노출되는 위험을 spec 차원에서 차단). Plan E가 Trash viewer에서 deleted item을 노출해야 할 때 별도 API (예: `fetchPhotoIncludingDeleted(id:)`)를 도입.
- 단, `runReaper`는 file system + DB row 비교가 본질이므로 `deletedAt` 무관하게 모든 row를 본다 (deleted row가 가리키는 file은 영구 삭제 시점까지 보존).

### 6.2 delete UI 부재 (decision D2)

- Plan C는 delete 진입점 노출 안 함 — 세션 카드 더보기 (`ellipsis.circle`)는 placeholder만, 메뉴 항목 비활성 또는 미노출.
- 이유: Trash viewer (복원 + 영구 삭제)는 Plan E. viewer 없이 delete만 있으면 사용자가 항목을 stranded 처리할 위험.
- Plan E가 `MediaStorage.deletePhoto(id:permanent:)` + `MediaStorage.restorePhoto(id:)` + `Trash` 화면을 일괄 도입.

### 6.3 reaper 영향 없음

- Plan B의 `runReaper`는 `Media/<UUID>.heic` 파일에 대응하는 Photo row 부재 시 정리. `deletedAt != nil`인 row는 여전히 존재하므로 reaper가 deleted item의 파일을 지우지 않음. Plan E에서 영구 삭제 시 row + 파일 삭제.

---

## 7. UX 흐름

### 7.1 갤러리 진입 (Phase 3.1)

```
Sites 탭 tap
├─ GalleryScreen.body
├─ .task { await refresh() }  // fetchSessionsWithPreview
└─ LazyVStack of SessionCardView
```

### 7.2 세션 카드 (Phase 3.2)

```
SessionCardView (한 세션)
├─ 4-photo preview Grid (2x2)
│   ├─ ThumbnailView × 4 (없으면 placeholder fill)
│   ├─ 4번째 위에 +N 배지 (totalPhotoCount > 4 일 때)
│   └─ 정사각형 비율
├─ 메타 row: 세션명 · 시간 · 위치명 · 사진 수
└─ 우측 액션: 공유 아이콘 · 더보기(disabled placeholder)
```

Tap 처리:
- preview 그리드 또는 메타 영역 → `SessionDetailScreen` push (NavigationStack)
- 공유 아이콘 → `ShareEntryButton` 시트 (전체 사진 공유)
- 더보기 → no-op (Plan E 예정)

### 7.3 세션 detail (Phase 3.4)

```
SessionDetailScreen
├─ navigation title: 세션명 (tap → 세션명 편집 sheet)
├─ navigation trailing: 메모 편집 버튼 + 공유 버튼
├─ Scrollable VStack
│   ├─ 헤더 (시간 · 위치명 · 사진 수)
│   └─ LazyVGrid (3 columns, 정사각형) of ThumbnailView × photo
└─ photo tap → PhotoDetailView (Plan B 산출 재사용)
```

### 7.4 세션명 / 메모 편집 (Phase 3.5)

PhotoMemoEditor의 sheet 패턴 그대로:
- NavigationStack + TextField/TextEditor + 취소/저장 toolbar.
- 빈 이름은 거부 (`SessionNameEditor.Error.emptyName`).
- 메모는 nil 허용.

### 7.5 ThumbnailView (Phase 3.3)

```swift
struct ThumbnailView: View {
    @EnvironmentObject private var deps: DependencyContainer
    let photo: Photo
    @State private var data: Data?
    @State private var task: Task<Void, Never>?

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.3))
            }
        }
        .clipped()
        .onAppear { task = Task { await load() } }
        .onDisappear { task?.cancel() }
    }
    @MainActor private func load() async {
        data = try? await deps.mediaStorage.loadThumbnailData(for: photo)
    }
}
```

### 7.6 Share 진입 UI (Phase 4.4)

세션 카드 또는 PhotoDetail의 공유 버튼 tap → confirmation dialog (또는 minimal sheet):

```
공유 옵션
☐ 위치 정보 포함 (기본 ON, 사진에 location 메타 있을 때만 활성)
☐ 촬영 시간 포함 (기본 ON)
[ 공유하기 ] (primary button → SharePreparer → ShareSheetController)
[ 취소 ]
```

토글 + 버튼 sheet는 SwiftUI native 컴포넌트로. ConfirmationDialog 보다는 sheet에 토글 + 버튼이 자연스러움.

---

## 8. 테스트 전략

### 8.1 Unit (Swift Testing, in-memory DB)

| 영역 | 테스트 |
|---|---|
| MediaStorage.fetchSessions* | 시간순 역방향, deletedAt 필터, 빈 결과, per-session N+1 회피 (1 또는 2 batched SQL, 세션 수에 비례한 SQL 호출 카운트 회귀 차단) |
| MediaStorage.fetchPhotos | sessionId 매칭, deletedAt 필터, 시간순 |
| MediaStorage.fetchSessionPreview | 4-photo cap, totalCount, 1장만 있는 세션 등 |
| MediaStorage.updateSessionName / Note | round-trip, notFound, emptyName |
| MediaStorage.loadThumbnailData | round-trip, cache hit/miss, canonical filename invariant |
| ThumbnailCoordinator | in-flight coalesce (동일 photo 동시 호출 → 1 generation), bounded concurrency (5번째 요청 wait) |
| ShareSanitizer | location strip on/off, GPS metadata 제거 검증, 시간 메타 유지, 디코딩 실패 throw |
| SharePreparer | 단일/다중 photo, 토글 조합 4종, 자동 텍스트 형식, tmp 디렉토리 생성 |
| SharePreparer.cleanupExpired | 24h 경과 디렉토리 정리, 최근 디렉토리 보존 |
| SessionNameEditor | round-trip, notFound, emptyName |
| SessionNoteEditor | round-trip, notFound, nil clear |

목표: ~30+ 신규 tests.

### 8.2 통합 (시뮬레이터)

- seeded capture (`MediaStorage.injectSeededCapture`) × 3 → 갤러리 → 세션 카드 → 진입 → 사진 그리드 → PhotoDetail → 메모 → 닫기 → 재진입 시 메모 유지.
- thumbnail cold/warm cache 동작 확인 (Xcode Instruments 또는 print log).

### 8.3 실기기 manual (§10)

---

## 9. 에러 처리

| 에러 | 처리 |
|---|---|
| `MediaStorage.Error.invalidFileName` (기존) | placeholder 유지 + log |
| `MediaStorage.Error.sessionNotFound` (신규) | alert "세션을 찾을 수 없어요" |
| `SessionNameEditor.Error.emptyName` | sheet 안에 inline 안내, 닫지 않음 |
| `SessionNoteEditor.Error.notFound` | alert + sheet 닫음 |
| `ShareSanitizer.Error.decodeFailed` | sharing 실패 alert "이미지를 준비할 수 없어요" + tmp cleanup |
| Thumbnail generation 실패 | placeholder 유지 + log (사용자에게 alert 없음) |
| disk full (writeThumb fail) | placeholder 유지, 다음 시도 재생성 (자가 회복) |

---

## 10. 실기기 manual checklist (Plan C 추가)

### 10.1 갤러리
- [ ] Sites 탭 진입 → 세션 카드 리스트 시간순 역방향
- [ ] cold cache 첫 진입 → placeholder 즉시, 0.5초 내 thumbnail 도착
- [ ] warm cache 재진입 → <0.3s 첫 화면 (Plan B에서 5+ 세션 시드 후)
- [ ] 스크롤 60fps (500+ 세션 시드 권장)
- [ ] 세션 카드 4-photo preview + +N 정상 (사진 < 4 / = 4 / > 4)
- [ ] preview 영역 또는 메타 tap → 세션 detail push

### 10.2 세션 detail
- [ ] 정사각형 photo grid 3 columns
- [ ] photo tap → PhotoDetailView (Plan B 동작 그대로)
- [ ] 네비게이션 title의 세션명 tap → sheet 편집 → 저장 → 헤더 갱신
- [ ] 빈 이름 저장 시도 → 에러 안내 + sheet 유지
- [ ] 메모 편집 sheet → TextEditor → 저장 → 다음 진입 시 유지
- [ ] PhotoDetailView 진입 후 메모 편집 → 닫기 → 세션 detail로 복귀 시 PhotoDetail 메모 + 세션 메모 둘 다 정상

### 10.3 Share v1 lite
- [ ] 세션 카드 공유 → 위치/시간 토글 → 공유하기 → UIActivityViewController 등장
- [ ] PhotoDetail 공유 → 동일
- [ ] 위치 토글 OFF + 사진 메타에 위치 있음 → 공유한 후 시스템 Files 앱으로 받아 EXIF 확인 시 GPS 없음
- [ ] 위치 토글 ON → GPS 그대로
- [ ] 시간 토글 OFF → 자동 텍스트에서 시간 빠짐 (메시지 입력 미리보기)
- [ ] 공유 완료 → `tmp/Camork/Share/<UUID>/` 디렉토리 삭제됨 (Xcode Files inspection)
- [ ] 공유 취소 → 동일하게 cleanup
- [ ] 앱 종료 후 24h 이상 경과 → 재시작 시 잔존 tmp cleanup
- [ ] iOS share sheet에서 KakaoTalk/Telegram 등 설치 앱으로 공유 → 받은 사진 + 자동 텍스트 확인

### 10.4 Trash query filter
- [ ] (DEBUG only seeded) `deletedAt` 수동 설정 photo → 갤러리/세션 detail에서 미노출
- [ ] 동일 — session.deletedAt 설정 → 갤러리에서 미노출
- [ ] delete UI는 v1 Core에 없음 — 더보기 메뉴 placeholder 확인

### 10.5 비주얼 / 접근성
- [ ] 다크/라이트 모두 정상 (갤러리 + 세션 detail + share sheet)
- [ ] Dynamic Type AX5 시 세션 카드 메타 잘림 없음
- [ ] VoiceOver: 카드 / preview / 공유 / 더보기 라벨 명확
- [ ] 한국어 / 영어 모두 정상

---

## 11. Plan D 인계 항목

### 11.1 Plan D 결정 필요

- 풀스펙 ShareComposer UX — 사전 텍스트 편집 미리보기 화면 layout
- Camork 측 channel ranking — 최근/자주 사용 채널 위로
- Camork 측 channel preselect — 사용자별 기본 공유 채널
- custom share UI — 시스템 share sheet 대신 Camork 자체 UI (시도할지)

### 11.2 Plan C에서 박아둔 인프라

- `SharePreparer` + `ShareSanitizer` — 재사용. Plan D는 위 사전 미리보기 UI를 추가 layer로 얹기만.
- `MediaStorage.fetchSessions/Photos` + `loadThumbnailData` — Plan D의 채널 ranking에서 최근 공유 통계 추가 시 schema 한 컬럼 추가 가능 (현재 미존재).

### 11.3 미해결 (Plan E 이후)

- Trash viewer UI
- delete / restore UI 노출 시점
- 영구 삭제 정책 (30일 자동 vs 사용자 명시)
- App Lock (Plan E)

---

## 12. 오픈 이슈 (writing-plans 단계에서 결정)

- 4-photo preview의 2x2 그리드 vs 1+3 그리드 (큰 첫 사진 + 작은 3장) — 결정 #5는 4+N 채택했으나 layout 정밀화는 frontend-design 단계로 미룸 (mockup 필요)
- 세션 카드 "더보기" 아이콘 자체 노출 여부 (Plan C delete UI 없음 → 더보기 메뉴가 빈약하면 아이콘 제거가 깔끔할 수도)
- ThumbnailCoordinator 동시성 limit 4 — 실기기 60fps 측정 후 조정
- SharePreparer 자동 텍스트의 placeName fallback (위치 메타에 placeName 없음 시 좌표 표시 vs 생략)
- `share_*` 로컬라이즈 키 목록 (final 카피는 frontend-design)

---

## 다음 단계

1. **사용자 + critique 검토** — 본 spec의 5 항목 (scope / thumbnail / share / trash / 모듈 구조) 충분한지 확인
2. **승인 후** — `superpowers:writing-plans` 스킬로 Phase 1~5 구현 계획 작성 (phase 별 / 파일 별 / 검증 단계 포함)
3. **그 다음** — TDD 기반 phase 단위 구현
