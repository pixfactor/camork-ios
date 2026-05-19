# Plan C — Gallery + Share v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:executing-plans` **Inline 모드**가 본 plan의 유일한 기본 실행 경로. subagent 분기(`superpowers:subagent-driven-development`)는 사용자가 명시 요청한 경우에만. 본 run의 default lane은 Inline 단일. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Plan B의 capture-save 파이프라인 위에 갤러리 + 안전한 공유 lite + 메모 UI를 얹어 v1 Core 출시 후보로 끌어올린다.

**Architecture:** master spec §4.3/§4.4 정렬. Plan B 산출(`PhotoDetailView`/`PhotoMemoEditor`/`MediaStorage` actor)을 그대로 재사용하며 갤러리 진입점 + thumbnail cache pipeline + ShareComposer-lite를 추가. raw HEIC list/grid 디코딩 금지(영속 thumb cache 경유), share는 sanitized temp copy 경로 필수, delete UI는 Plan C 비노출(Trash viewer는 Plan E).

**Tech Stack:** Swift 5.0 + SwiftUI + AVFoundation + ImageIO + UIKit (UIActivityViewController) + GRDB 7.10.0 + XcodeGen + Swift Testing.

**참조:**
- spec: `docs/superpowers/specs/2026-05-19-camork-v1-core-C-gallery-design.md` (89f9573)
- Plan B 보고서: `docs/superpowers/reports/2026-05-19-plan-B-storage-camera-complete.md`
- master spec §4.3/§4.4/§9.1/§12

**검증 환경:**
- xcodegen generate → xcodebuild test on iPhone 17 Pro simulator
- jq empty Localizable.xcstrings
- Lore Commit Protocol (why-first first line + Constraint/Rejected/Confidence/Scope-risk/Directive/Tested/Not-tested trailers)
- push 보류 (사용자 명시 승인까지)

---

## Phase 1 — 갤러리 데이터 API (TDD red→green)

### Task 1.1 — fetchSessions / fetchPhotos + deletedAt 필터

**Files:**
- Modify: `Camork/Sessions/MediaStorage.swift` — 신규 메서드 + nested `enum SessionSort`
- Test: `CamorkTests/MediaStorageTests.swift` — 신규 5건

- [ ] **Step 1: 실패 테스트 작성**

```swift
@Test("fetchSessions: 시간순 역방향 반환")
func fetchSessionsOrdering() async throws { ... }

@Test("fetchSessions: deletedAt non-null 세션 제외")
func fetchSessionsFiltersDeleted() async throws { ... }

@Test("fetchSessions: 빈 결과")
func fetchSessionsEmpty() async throws { ... }

@Test("fetchPhotos: sessionId 매칭 + 시간순")
func fetchPhotosBasic() async throws { ... }

@Test("fetchPhotos: deletedAt non-null photo 제외")
func fetchPhotosFiltersDeleted() async throws { ... }
```

- [ ] **Step 2: red 확인** — `cannot find 'fetchSessions' in scope`

- [ ] **Step 3: 구현**

```swift
enum SessionSort: Sendable { case createdAtDesc }

actor MediaStorage {
    func fetchSessions(sortedBy: SessionSort = .createdAtDesc) async throws -> [Session] {
        try await db.read { db in
            try Session
                .filter(Column("deletedAt") == nil)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    func fetchPhotos(sessionId: UUID) async throws -> [Photo] {
        try await db.read { db in
            try Photo
                .filter(Column("sessionId") == sessionId.uuidString)
                .filter(Column("deletedAt") == nil)
                .order(Column("capturedAt").asc)
                .fetchAll(db)
        }
    }
}
```

- [ ] **Step 4: green 확인** — `xcodebuild test` PASS
- [ ] **Step 5: Lore commit** — 첫 줄: `expose gallery query API for plan C`

### Task 1.2 — SessionPreview + fetchSessionsWithPreview (N+1 회피)

**Files:**
- Modify: `Camork/Sessions/MediaStorage.swift` — `struct SessionPreview` + `SessionWithPreview` + `fetchSessionPreview` + `fetchSessionsWithPreview`
- Test: `CamorkTests/MediaStorageTests.swift` — 신규 4건

- [ ] **Step 1: 실패 테스트**

```swift
@Test("fetchSessionPreview: 4개 photo cap + total count 정확")
func sessionPreview4Cap() async throws { ... }

@Test("fetchSessionPreview: photos < 4 인 세션은 그대로")
func sessionPreviewLessThanFour() async throws { ... }

@Test("fetchSessionsWithPreview: per-session N+1 회피")
func sessionsWithPreviewNoNPlus1() async throws {
    // 10개 세션 + 각 5개 photo seed → fetchSessionsWithPreview 호출 시
    // SQL 호출 카운트가 세션 수에 비례하지 않음 (1 또는 2 batched SQL).
    // db.trace hook으로 측정.
}

@Test("fetchSessionsWithPreview: deletedAt 필터 + capturedAt DESC preview")
func sessionsWithPreviewOrdering() async throws { ... }
```

- [ ] **Step 2: red 확인**
- [ ] **Step 3: 구현** — per-session N+1 회피가 invariant. 구현 가설은 (a) 1 SQL with window function 또는 (b) 2 batched SQL (sessions fetch + 가시/최근 세션의 preview photos를 한 번에). 어느 쪽이든 세션 수에 비례하는 호출 카운트는 차단. spec §3.2 그대로.
- [ ] **Step 4: green 확인**
- [ ] **Step 5: Lore commit**

### Task 1.3 — updateSessionName / Note + SessionNameEditor / SessionNoteEditor

**Files:**
- Modify: `Camork/Sessions/MediaStorage.swift` — `MediaStorage.Error.sessionNotFound` + `updateSessionName` + `updateSessionNote`
- Create: `Camork/Sessions/SessionNameEditor.swift`
- Create: `Camork/Sessions/SessionNoteEditor.swift`
- Test: `CamorkTests/SessionNameEditorTests.swift` (3건)
- Test: `CamorkTests/SessionNoteEditorTests.swift` (3건)

- [ ] **Step 1-5**: PhotoMemoEditor 패턴 mirror. Name editor는 `emptyName` 에러 추가.

### Task 1.4 — fetchPhoto(id:) deletedAt 강제

**Files:**
- Modify: `Camork/Sessions/MediaStorage.swift` — `fetchPhoto` 쿼리에 `WHERE deletedAt IS NULL`
- Test: `CamorkTests/MediaStorageTests.swift` — 신규 1건

- [ ] **Step 1: 테스트** — `fetchPhoto(id:)`에 deletedAt이 set된 photo → nil 반환 검증
- [ ] **Step 2-4**: red→green→commit
- [ ] caller (PhotoDetailView 등) 영향 없음 (기존 nil 처리 그대로)

---

## Phase 2 — Thumbnail cache pipeline (성능 §12 충족)

### Task 2.1 — FileOps.readThumb / writeThumb / removeThumb + MediaFileSystem 구현

**Files:**
- Modify: `Camork/Storage/FileOps.swift` — protocol 확장 (3 메서드 + thumbnail 디렉토리 bootstrap)
- Modify: `Camork/Storage/MediaFileSystem.swift` — `thumbDir` (Library/Caches/Camork/Thumbnails/) + 구현 + Data Protection 적용
- Modify: `CamorkTests/FakeFileOps.swift` — Dict 확장 (`thumbContents`)
- Test: `CamorkTests/MediaFileSystemTests.swift` — 신규 3건 (write/read/remove + Data Protection 검증)

- [ ] **Step 1-5**: TDD red→green→commit. `MediaFileSystem.init`에서 thumb 디렉토리는 caches base (`FileManager.url(for: .cachesDirectory)` + "Camork/Thumbnails")로 분리. Data Protection은 directory + writeThumb options 둘 다 적용.

### Task 2.2 — ThumbnailGenerator (pure helper)

**Files:**
- Create: `Camork/Sessions/ThumbnailGenerator.swift` — `enum ThumbnailGenerator` static func
- Test: `CamorkTests/ThumbnailGeneratorTests.swift` — 신규 4건

- [ ] **Step 1: 실패 테스트**

```swift
@Test("ThumbnailGenerator: 원본 Data → JPEG 0.8, 짧은 변 400pt × scale")
func generateBasic() throws { ... }

@Test("ThumbnailGenerator: 비율 유지 (정사각형/세로/가로 원본)")
func generateAspectRatio() throws { ... }

@Test("ThumbnailGenerator: 디코딩 실패 시 throw (4-byte fake data)")
func generateDecodeFailure() throws { ... }

@Test("ThumbnailGenerator: 출력 size가 원본보다 크면 원본 그대로 (upscale 방지)")
func generateNoUpscale() throws { ... }
```

- [ ] **Step 2-5**: ImageIO downscale (`CGImageSourceCreateThumbnailAtIndex` 또는 `UIImage.preparingThumbnail(of:)`). Off-main 호출.

### Task 2.3 — ThumbnailCoordinator (in-flight coalesce + bounded concurrency)

**Files:**
- Create: `Camork/Sessions/ThumbnailCoordinator.swift` — actor
- Modify: `Camork/Sessions/MediaStorage.swift` — `loadThumbnailData(for:)` public API
- Test: `CamorkTests/ThumbnailCoordinatorTests.swift` — 신규 5건

- [ ] **Step 1: 실패 테스트**

```swift
@Test("Coordinator: cache hit 즉시 반환")
func cacheHit() async throws { ... }

@Test("Coordinator: cache miss → 생성 + write + 반환")
func cacheMiss() async throws { ... }

@Test("Coordinator: 동일 photo 동시 호출 → 1 generation (in-flight coalesce)")
func coalesce() async throws {
    // 10 concurrent loadThumbnailData(for: same photo)
    // → ThumbnailGenerator 호출 카운트 == 1
}

@Test("Coordinator: bounded concurrency 4 — 5번째 요청은 대기")
func boundedConcurrency() async throws { ... }

@Test("Coordinator: canonical fileName invariant (Plan B와 동일)")
func invalidFileNameRejected() async throws { ... }
```

- [ ] **Step 2-5**: actor + `[UUID: Task<Data, Error>]` inFlight map + counter semaphore. `MediaStorage.loadThumbnailData(for:)`는 coordinator 위임.

### Task 2.4 — runReaper 확장 (thumbnail orphan)

**Files:**
- Modify: `Camork/Sessions/MediaStorage.swift` — `runReaper`에 thumbnail enumerate + DB photo id set 비교
- Modify: `Camork/Storage/FileOps.swift` + `MediaFileSystem.swift` — `enumerateThumb()` 추가
- Modify: `CamorkTests/FakeFileOps.swift` — 동일 확장
- Test: `CamorkTests/MediaStorageTests.swift` — 신규 1건 (orphan thumb cleanup)

- [ ] **Step 1-5**: TDD.

---

## Phase 3 — Gallery UI

### Task 3.1 — GalleryScreen (스켈레톤 + 데이터 wiring)

**Files:**
- Create: `Camork/Gallery/GalleryScreen.swift`
- Modify: `Camork/Resources/Localizable.xcstrings` — 신규 키 (`gallery_empty_*`, `gallery_loading` 등)

- [ ] **Step 1**: 스켈레톤 SwiftUI View (`@EnvironmentObject deps`, `@State sessions: [SessionWithPreview]`, `@State isLoading: Bool`)
- [ ] **Step 2**: `.task { await refresh() }` + `refresh()`에서 `fetchSessionsWithPreview` 호출
- [ ] **Step 3**: empty state + loading state UI
- [ ] **Step 4**: 빌드 검증 (단위 테스트 없음, UI는 manual)
- [ ] **Step 5**: Lore commit

### Task 3.2 — SessionCardView (4+N preview + 메타)

**Files:**
- Create: `Camork/Gallery/SessionCardView.swift`
- Modify: `Camork/Resources/Localizable.xcstrings` — `session_card_photo_count` plural 등

- [ ] **Step 1**: 2×2 LazyVGrid (정사각형) of ThumbnailView × 4 (없으면 placeholder fill)
- [ ] **Step 2**: 4번째 위에 "+N" 배지 (totalCount > 4 일 때)
- [ ] **Step 3**: 메타 row (세션명 · 시간 formatted · 위치명 · 사진 수)
- [ ] **Step 4**: 우측 액션 — share button (Phase 4 wiring) + 더보기 (disabled placeholder)
- [ ] **Step 5**: 빌드 + Lore commit

### Task 3.3 — ThumbnailView SwiftUI 컴포넌트

**Files:**
- Create: `Camork/Gallery/ThumbnailView.swift`

- [ ] **Step 1**: `@EnvironmentObject deps` + `let photo: Photo` + `@State data: Data?` + `@State task: Task?`
- [ ] **Step 2**: `.onAppear { task = Task { await load() } }` + `.onDisappear { task?.cancel() }`
- [ ] **Step 3**: `load()`에서 `try? await deps.mediaStorage.loadThumbnailData(for: photo)` 호출, MainActor에 data 설정
- [ ] **Step 4**: placeholder fallback (RoundedRectangle + secondary opacity)
- [ ] **Step 5**: Lore commit

### Task 3.4 — SessionDetailScreen (정사각형 grid)

**Files:**
- Create: `Camork/Gallery/SessionDetailScreen.swift`
- Modify: `Camork/Resources/Localizable.xcstrings` — `session_detail_*` 키

- [ ] **Step 1**: `@EnvironmentObject deps` + `let session: Session` + `@State photos: [Photo]` + `@State sheet: SessionDetailSheet?`
- [ ] **Step 2**: navigation title (세션명) + 메모 편집 / 공유 toolbar items
- [ ] **Step 3**: LazyVGrid (3 columns, GridItem.adaptive 또는 fixed) of ThumbnailView
- [ ] **Step 4**: photo tap → PhotoDetailView fullScreenCover (CameraScreen 패턴 재사용)
- [ ] **Step 5**: Lore commit

### Task 3.5 — SessionNameEditor / SessionNoteEditor sheet UI

**Files:**
- Create: `Camork/Gallery/SessionNameEditSheet.swift`
- Create: `Camork/Gallery/SessionNoteEditSheet.swift`
- Modify: `Camork/Resources/Localizable.xcstrings`

- [ ] **Step 1**: NavigationStack + TextField/TextEditor + 취소/저장 toolbar (PhotoMemoEditor sheet 패턴 mirror)
- [ ] **Step 2**: 저장 실패 시 alert (`Error.notFound` / `Error.emptyName`)
- [ ] **Step 3**: 빈 이름 검증 (Name) — sheet 안에 inline 안내
- [ ] **Step 4**: 빌드 + Lore commit

### Task 3.6 — RootTabView 교체

**Files:**
- Modify: `Camork/RootTabView.swift` — `GalleryPlaceholderView` → `GalleryScreen`

- [ ] **Step 1**: 한 줄 교체 + #Preview 보류 사유 그대로 유지
- [ ] **Step 2**: 빌드 + Lore commit

---

## Phase 4 — Share v1 lite

### Task 4.1 — ShareSanitizer (static pure)

**Files:**
- Create: `Camork/Share/ShareSanitizer.swift`
- Test: `CamorkTests/ShareSanitizerTests.swift` — 신규 5건

- [ ] **Step 1: 실패 테스트**

```swift
@Test("location ON: GPS dict 유지")
func locationKeepsGPS() throws { ... }

@Test("location OFF: GPS dict 제거 (EXIF+XMP 양쪽)")
func locationStripsGPS() throws { ... }

@Test("orientation 메타 보존 (90도 회전 입력 → 출력 동일)")
func orientationPreserved() throws { ... }

@Test("DateTimeOriginal 보존 (location 토글과 무관)")
func dateTimeOriginalPreserved() throws { ... }

@Test("ICC color profile 보존")
func colorProfilePreserved() throws { ... }
```

- [ ] **Step 2: red 확인**
- [ ] **Step 3: 구현** — `CGImageSource` + `CGImageDestination` + `kCGImageDestinationMetadata` 조작. GPS는 dictionary 통째 제거. Orientation/ColorProfile/DateTimeOriginal 키만 copy.
- [ ] **Step 4-5**: green + Lore commit

### Task 4.2 — SharePreparer actor

**Files:**
- Create: `Camork/Share/SharePreparer.swift`
- Test: `CamorkTests/SharePreparerTests.swift` — 신규 6건

- [ ] **Step 1: 실패 테스트**

```swift
@Test("prepare: 단일 photo + location ON + time ON → tmp/Share/<UUID>/photo-0.heic + 자동 텍스트")
func singlePhotoBothOn() async throws { ... }

@Test("prepare: 다중 photo")
func multiplePhotos() async throws { ... }

@Test("자동 텍스트 형식: location/time 토글 조합 4종")
func autoTextVariants() async throws { ... }

@Test("위치 OFF → ShareSanitizer가 GPS strip한 사본 작성")
func locationOffSanitizes() async throws { ... }

@Test("cleanup: ShareBundle.tempDir 삭제 시 파일 사라짐")
func cleanupRemoves() async throws { ... }

@Test("cleanupExpired: 24h 이상 orphan만 정리, 최근 보존")
func cleanupExpiredAge() async throws { ... }
```

- [ ] **Step 2-5**: actor 구현. 임시 디렉토리는 `FileManager.default.temporaryDirectory.appendingPathComponent("Camork/Share/<UUID>", isDirectory: true)` 사용 — temporaryDirectory가 명시적이고 cleanup target 경로 일관.

### Task 4.3 — ShareSheetController (UIViewControllerRepresentable)

**Files:**
- Create: `Camork/Share/ShareSheetController.swift`
- Test: (build verification only — UIActivityViewController는 단위 테스트 부적합)

- [ ] **Step 1**: UIViewControllerRepresentable wrap `UIActivityViewController(activityItems:)`
- [ ] **Step 2**: completionWithItemsHandler에서 onCompletion callback 호출
- [ ] **Step 3**: 빌드 + Lore commit (단위 테스트 없음, manual에서 검증)

### Task 4.4 — ShareEntryButton SwiftUI

**Files:**
- Create: `Camork/Share/ShareEntryButton.swift`
- Modify: `Camork/Resources/Localizable.xcstrings` — `share_*` 키 5+개

- [ ] **Step 1**: sheet with 위치/시간 토글 + "공유하기" primary + 취소 button
- [ ] **Step 2**: 공유하기 tap → SharePreparer.prepare → ShareSheetController fullScreenCover/sheet
- [ ] **Step 3**: completion handler에서 cleanup + 닫기
- [ ] **Step 4**: SessionCardView + PhotoDetailView (or SessionDetailScreen toolbar)에 wiring
- [ ] **Step 5**: Lore commit

### Task 4.5 — Bootstrap 시 tmp cleanup

**Files:**
- Modify: `Camork/AppShell/DependencyContainer.swift` — init 끝에서 `Task { await sharePreparer.cleanupExpired() }`
- Test: 통합 — Bootstrap 후 tmp 디렉토리 24h 이상 항목 정리 확인

- [ ] **Step 1-5**: SharePreparer를 deps에 보유 + Bootstrap에서 비동기 cleanup. Plan B Phase 4의 Bootstrap test 회귀 확인.

---

## Phase 5 — 통합 회귀 + manual + 보고서

### Task 5.1 — Clean build + 전체 회귀

```bash
xcodegen generate && \
xcodebuild clean -scheme Camork && \
xcodebuild -scheme Camork \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
  test 2>&1 | tail -25
```

Expected: 모든 테스트 통과 (Plan B 누적 90 + Plan C 신규 ~30+건), 0 test failures + 0 compiler errors. AppIntents 메타데이터 경고는 known non-blocking.

### Task 5.2 — 실기기 manual checklist

spec §10 카테고리 전체 (갤러리 / 세션 detail / share v1 / trash filter / 비주얼 접근성). 27 항목.

### Task 5.3 — Plan C 완료 보고서

**Files:**
- Create: `docs/superpowers/reports/2026-05-19-plan-C-gallery-share-complete.md`

내용:
- §1 산출 phase × commit 매핑
- §2 검증 결과 (xcodebuild + jq + 회귀 카운트)
- §3 Phase 3.2 corrective 등 mid-pass amend가 있었다면 기록
- §4 실기기 manual 결과
- §5 Plan D 인계 (풀스펙 ShareComposer UX / channel ranking) + Plan E 인계 (Trash viewer / AppLock)
- §6 미해결 / gap

---

## Phase 1~5 누적 신규 테스트 예상치

| Phase | Suite | Tests |
|---|---|---|
| 1.1 | MediaStorage (확장) | +5 |
| 1.2 | MediaStorage (확장) | +4 |
| 1.3 | SessionNameEditor + SessionNoteEditor | +6 |
| 1.4 | MediaStorage (확장) | +1 |
| 2.1 | MediaFileSystem (확장) | +3 |
| 2.2 | ThumbnailGenerator | +4 |
| 2.3 | ThumbnailCoordinator | +5 |
| 2.4 | MediaStorage (확장) | +1 |
| 3.x | (UI — build verification only) | 0 |
| 4.1 | ShareSanitizer | +5 |
| 4.2 | SharePreparer | +6 |
| 4.3-4.5 | (UI — build verification + manual) | 0 |
| **합계** | | **+40** |

**예상 총 누적**: Plan B 90 + Plan C 40 = **130 tests**

---

## 사용 스킬

- `superpowers:executing-plans` (Inline 모드) — 기본 실행 경로 (Plan A/B에서 채택)
- TDD discipline: red → green → Lore commit per task

**선택적 review pass (사용자 명시 요청 시에만):**
- `oh-my-claudecode:ai-slop-cleaner` — docs hygiene amend가 필요한 cleanup 상황
- `frontend-engineer` subagent — 복잡한 SwiftUI layout 정밀화가 필요할 때

기본 실행에는 위 두 skill을 호출하지 않음 — routing noise 회피.

## 실행 순서 (Inline 모드)

inline 모드로 Phase 1.1 → 1.2 → ... → 5.3 순차. **각 Task는 verification 통과 시 다음 Task로 auto-continue** (TDD red → green → Lore commit cycle). 사용자에게 묻는 경우는 (1) push, (2) destructive 작업 (git reset --hard, branch -D, force-push 등), (3) credentials / external production 변경, (4) material scope change (phase 추가/축소). 큰 corrective pass는 amend로 박음. push는 Phase 5.3 보고서 + 사용자 명시 승인 후.

---

## 미해결 (writing-plans 단계에서 처리 보류)

spec §12와 동일:
- 4+N preview 정밀 layout (2×2 vs 1+3)
- 더보기 아이콘 노출 여부
- ThumbnailCoordinator 동시성 limit 실측 조정
- placeName fallback (좌표 vs 생략)
- share localization keys final 카피
