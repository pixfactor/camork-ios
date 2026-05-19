# Plan B 완료 보고서 — Storage + Camera

- **작성일:** 2026-05-19
- **브랜치:** rebuild/v2 (push 보류 유지, origin 대비 +33 commits)
- **마스터 spec:** `docs/superpowers/specs/2026-05-19-camork-rebuild-design.md`
- **Plan B spec:** `docs/superpowers/specs/2026-05-19-camork-v1-core-B-storage-camera-design.md` (v3.3)
- **Plan B plan:** `docs/superpowers/plans/2026-05-19-camork-v1-core-B-storage-camera.md` (v1.4)
- **Phase 1.0 ADR:** `docs/superpowers/adrs/2026-05-19-storage-and-concurrency.md`

---

## 1. 산출

### 1.1 코드

| Phase | Files | Tests | Commit |
|---|---|---|---|
| 1.0 ADR | adrs/2026-05-19-storage-and-concurrency.md | — | `d0df54a` |
| 1.1 GRDB SPM | project.yml + Package.resolved tracked | — | `d3c6fed` |
| 1.2 Database + Migrations | Storage/Database.swift + Storage/Migrations.swift | 5 | `86cefba` |
| 1.3 Models | Storage/{Photo,Session,LocationSnapshot,MediaKind,ExifData}.swift | — | `a3795de` |
| 1.4 FileOps + MediaFileSystem | Storage/{FileOps,MediaFileSystem}.swift | 6 | `8017d0f` |
| 1.5 SessionAssignmentPolicy | Sessions/{PhotoCapturePayload,SessionAssignmentPolicy}.swift | 10 | `5fb3217` |
| 1.6 MediaStorage actor | Sessions/{MediaStorage,MediaStorageTestHooks}.swift + FakeFileOps | 12 | `3570889` |
| 2a.1 PermissionsService | Services/PermissionsService.swift | 9 | `0e97992` |
| 2a.2 CameraSessionBuilder + ExifBuilder | Camera/Internal/{CameraSessionBuilder,ExifBuilder}.swift | 8 | `a9bc389` |
| 2a.3 CameraSession | Camera/CameraSession.swift | — | `4b6afb8` |
| 2b.1 LocationService | Services/LocationService.swift | 10 | `488ac3c` |
| 2b.2 MediaCapture | Camera/MediaCapture.swift | — | `4476f76` |
| 2c.1 DependencyContainer + StorageInitErrorView | AppShell/{DependencyContainer,StorageInitErrorView}.swift + CamorkApp.swift + xcstrings | — | `ed951e8` |
| 2c.2 CameraScreenViewState | Camera/Internal/CameraScreenViewState.swift | 13 | `527f7ee` |
| 2c.3 CameraView | Camera/CameraView.swift | 1 | `c594b2e` |
| 2c.4 CameraScreen | Camera/CameraScreen.swift + xcstrings | — | `9250051` (amended from `4880739`) |
| 2c.5 RootTabView 교체 | RootTabView.swift | — | `70825f8` |
| (docs polish) | CameraSession.swift + RootTabView.swift docs | — | `70d2458` |
| 3.1 PhotoMemoEditor | Sessions/PhotoMemoEditor.swift | 3 | `b07c282` |
| 3.2 PhotoDetailView + zoom + storage API + xcstrings | Gallery/PhotoDetailView.swift + Sessions/MediaStorage.swift + Storage/{FileOps,MediaFileSystem}.swift + Camera/CameraScreen.swift + FakeFileOps + xcstrings | 6 | `4eaa3ec` (amended from `d53f9a6`) |

**총 33 commits, 90 tests, 14 suites.**

### 1.2 ADR & 보고서

- Phase 1.0 ADR — 12 항목 (Storage + Concurrency 단일 권위 결정서)
- 본 완료 보고서

---

## 2. 검증 결과 (Task 4.1)

### 2.1 Clean build + 전체 회귀

```bash
xcodegen generate
xcodebuild clean -scheme Camork
xcodebuild -scheme Camork \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
  test
```

**결과:**
- ⚙️ xcodegen generate → SUCCEEDED
- 🧹 xcodebuild clean → **CLEAN SUCCEEDED**
- ✅ xcodebuild test → **TEST SUCCEEDED**
- 📊 **90 tests in 14 suites passed in 1.55s**
- 📋 0 test failures / 0 compiler errors; 2 알려진 non-blocking AppIntents 메타데이터 경고 ("Metadata extraction skipped. No AppIntents.framework dependency found.") — v1 Core는 AppIntents framework 미사용이라 무관
- 📁 xcstrings 검증: `jq empty Localizable.xcstrings` → OK

### 2.2 Suite 분포

| Suite | Tests | Phase |
|---|---|---|
| Theme tokens | 3 | Plan A |
| Semantic colors | 2 | Plan A |
| CamorkButton style resolution | 2 | Plan A |
| Migrations | 5 | 1.2 |
| MediaFileSystem | 6 | 1.4 |
| SessionAssignmentPolicy | 10 | 1.5 |
| MediaStorage | 18 | 1.6 + 3.2 |
| PermissionsService | 9 | 2a.1 |
| CameraSessionBuilder | 4 | 2a.2 |
| ExifBuilder | 4 | 2a.2 |
| LocationService | 10 | 2b.1 |
| CameraScreenViewState | 13 | 2c.2 |
| CameraView | 1 | 2c.3 |
| PhotoMemoEditor | 3 | 3.1 |
| **합계** | **90** | |

### 2.3 빌드 진단

- xcodebuild 출력 기준: 0 test failures + 0 compiler errors
- **알려진 non-blocking 경고 2건**: AppIntents 메타데이터 추출 스킵 — `Metadata extraction skipped. No AppIntents.framework dependency found.` v1 Core 기능셋에 AppIntents가 포함되지 않으므로 무시 가능 (Plan E의 Siri/Shortcuts 진입 시 재검토)
- SourceKit-LSP에서 보고되던 GRDB / Camork / Testing 모듈 미해석 진단은 SPM 미해석 노이즈 — 실제 컴파일러 출력에는 부재. CI 검증 기준은 `xcodebuild`
- **§2.2 테이블 sanity check**: 14 unique suite rows × 합계 90 (3+2+2+5+6+10+18+9+4+4+10+13+1+3 = 90)

---

## 3. 핵심 아키텍처 결정 요약 (Phase 1.0 ADR 12 항목)

1. **GRDB DatabaseQueue + WAL + FK ON** — single writer + small dataset.
2. **단일 actor MediaStorage** — capture-save 흐름의 유일한 writer (SessionManager 분리 미채택, split-brain 회피).
3. **Failure matrix 4 buckets** — staging/mv/commit/crash. orphan reaper로 commit-안된 잔존물 정리.
4. **SessionAssignmentPolicy: pure struct** — actor 의존 없음, 단위 테스트 직진.
5. **@MainActor 적용 범위** — SwiftUI/ObservableObject만, domain struct는 Sendable로 actor 외부 사용.
6. **AVFoundation callback → MediaStorage hop** — non-Sendable AVCapturePhoto는 hop 금지, PhotoCapturePayload (Sendable)만 actor 통과.
7. **Cross-actor 통신: `await` 직접 호출만** — Combine은 UI 전용.
8. **Reentrancy 회피** — captured manualFlag 패턴 + 조건부 wipe.
9. **DI: Singleton 금지, App root container** — `try!` 금지 → `Bootstrap.pending/ready/failed`.
10. **테스트 전략** — in-memory `DatabaseQueue` (production config 공유) + temp dir + `FakeFileOps` + `MediaStorageTestHooks` (DEBUG only).
11. **ExifData** — 모든 필드 옵셔널, JSON blob 직렬화.
12. **isExcludedFromBackup + Data Protection** — DB + media + thumbnail 모두. `completeUntilFirstUserAuthentication`.

---

## 4. Phase 3.2 corrective pass 반영사항

`d53f9a6` → `4eaa3ec` amend에서 Codex 독립 검토 후 3건 정정:

1. **Zoom 미구현 정정** — `Image.scaledToFit()` → `ZoomableImageView` (UIScrollView + UIImageView + UITapGestureRecognizer). pinch 1.0~4.0 + 더블탭 toggle 2.0x + pan. spec 7.2 / 10.4 / Plan Step 2 충족.
2. **MediaStorage 경계 좁힘** — `loadPhotoData(for fileName: String)` → `loadPhotoData(for photo: Photo)`. actor 내부에서 canonical invariant (`name == "\(photo.id.uuidString).heic"` + path traversal 검사) 강제. `MediaStorage.Error.invalidFileName` 신설.
3. **metaBar stale state 정정** — `photo.note` (let) → 로컬 `@State savedNote: String?`. 저장 즉시 note.text 아이콘 반영.

---

## 5. 실기기 manual checklist (Task 4.2)

**상태: TODO** — 본 보고서가 작성된 시점에는 시뮬레이터 환경만 가용. 실기기 검증은 사용자가 다음 항목을 순차 수행하고 결과를 본 절에 추가.

### 5.1 카메라 lifecycle (spec §10.1)
- [ ] 앱 첫 시작 → 카메라 권한 요청 prompt 뜸
- [ ] 권한 허용 → 뷰파인더 정상 표시
- [ ] 권한 거부 → 안내 화면 (`camera_permission_denied_*`)
- [ ] 셔터 탭 → thumbnail 갱신 + 셔터 재활성화
- [ ] 백그라운드 진입 시 카메라 세션 정지 + LocationService.stopUpdates
- [ ] 백그라운드 → 복귀 시 카메라 자동 재시작 + 권한 granted면 LocationService.startUpdates

### 5.2 저장 검증 (spec §10.2)
- [ ] `~/Library/Application Support/Camork/Media/<UUID>.heic` 파일 존재 확인
- [ ] DB 파일 (`camork.sqlite`) 생성됨 (Metadata 디렉토리)
- [ ] **isExcludedFromBackup = true 검증** (Xcode Organizer 또는 device backup container)
- [ ] 위치 권한 허용 시 `Photo.location ≠ nil`
- [ ] 위치 권한 거부 시 `Photo.location == nil` (정상 저장)
- [ ] Failure matrix 실기기 시뮬 — orphan 파일 생성 시 다음 앱 시작 시 reaper 정리

### 5.3 세션 자동 묶기 (spec §10.3 + §10.3.1)
- [ ] 첫 촬영 → 새 세션 생성
- [ ] 같은 자리 연속 촬영 → 같은 세션 누적
- [ ] 30분 이상 무촬영 후 촬영 → 새 세션
- [ ] 다른 장소 이동 (Xcode Location Simulation) → 새 세션
- [ ] "새 현장" 칩 탭 → 다음 촬영이 새 세션
- [ ] 셔터 연타 5초/10회 → 모든 사진 저장 + DB count 일치
- [ ] 촬영 중 권한 회수 → 앱 복귀 시 권한 안내 화면 전환

### 5.4 PhotoDetail + 메모 (spec §10.4)
- [ ] thumbnail 탭 → 풀스크린 진입
- [ ] **ZoomableImageView**: 핀치 줌 / 더블탭 줌 / 팬 동작
- [ ] 메모 편집 → 저장 → 메타바 note.text 아이콘 즉시 표시 (savedNote 검증)
- [ ] 메모 편집 → 취소 → buffer revert
- [ ] 메모 nil 저장 (clear)
- [ ] 디테일 닫기 → 재진입 시 메모 유지

### 5.5 비주얼 / 접근성 (spec §10.5)
- [ ] 다크 모드 / 라이트 모드 모두 정상
- [ ] Dynamic Type AX5에서 깨짐 없음
- [ ] VoiceOver: shutter / new-site chip / 디테일 닫기·편집 라벨 명확
- [ ] 한국어 / 영어 모두 잘림 없음

---

## 6. Plan C 인계 (spec §11)

### 6.1 결정 필요 (Plan C 진입 시점)

1. 갤러리 메인 layout — 세션 카드 리스트 정렬, 시간 필터, 검색바
2. 세션 카드 디자인 — 프리뷰 그리드/콜라주, 메타 위치
3. 시간 필터 칩 — 전체/7일/이번 달 외 추가
4. 지도 토글 — Plan C vs Plan D
5. 세션 진입 후 UI — 그리드 vs 시간순 리스트
6. 세션 이름 편집 — 인라인 vs sheet

### 6.2 Plan B에서 박아둔 인프라

- `actor MediaStorage`에 `fetchSessions(filter:)`, `fetchPhotos(sessionId:)` API 미존재 — Plan C에서 추가.
- 휴지통 (`deletedAt`) 컬럼은 v1 schema에 이미 존재 — Plan C에서 UI 노출.
- `PhotoDetailView`는 Plan C 갤러리 진입점에서 재사용 가능 (init 시그너처 unchanged).
- `PhotoMemoEditor`는 갤러리/디테일 어느 진입점에서도 동일 사용.

### 6.3 미해결 (출시 전)

- AccentColor 정확 hex (Plan E)
- App Icon (Plan E)
- 영문 카피 정밀화 (Plan E)
- Swift 6 전환 — Plan A 보고서 인계 항목, Plan B Storage ADR 완료 후 별도 결정

### 6.4 Plan B 추가 발견 (gap)

- **PhotoDetailView #Preview (Dark/Light/AX5)** — `PhotoMemoEditor`가 실제 `MediaStorage` 인스턴스를 요구하여 preview 환경에서 mock이 비-trivial. 가벼운 `DependencyContainer` test seam 도입 시 일괄 추가 예정.
- **RootTabView #Preview** — 동일 사유로 보류.
- **시뮬레이터 Plan B Phase 4 실제 실행** — `CameraSession` init이 시뮬레이터에 카메라 없음으로 `.noDevice` throw → `StorageInitErrorView` 진입. 실제 캡쳐 흐름 시연은 실기기에서만 가능.
- **CameraSession off-main start/stop ownership 이전** — 현재 `CameraScreen`이 `cameraSessionQueue`를 보유하고 `cameraSession.start()/stop()`을 dispatch. `@unchecked Sendable`로 최소 옵트인 처리. 향후 `CameraSession`이 자체 queue + async start/stop API를 노출하도록 리팩터링 검토 (실기기 검증 후 판단).

---

## 7. Plan B 누적 commit 목록

```
4eaa3ec 3.2 PhotoDetailView + ZoomableImageView + storage boundary + savedNote (amended)
b07c282 3.1 PhotoMemoEditor (3 tests)
70d2458 (docs) CameraSession Sendable rationale + RootTabView preview comment
70825f8 2c.5 RootTabView → CameraScreen
9250051 2c.4 CameraScreen + LocationService lifecycle + LocalizedStringKey safeguard (amended)
c594b2e 2c.3 CameraView + 1 test (layerClass invariant)
527f7ee 2c.2 CameraScreenViewState + 13 tests
ed951e8 2c.1 DependencyContainer + StorageInitErrorView
4476f76 2b.2 MediaCapture (Sendable payload + actor hop ready)
488ac3c 2b.1 LocationService + 10 tests (sync latestKnown, no CL prompts)
4b6afb8 2a.3 CameraSession + typed CameraSessionError
a9bc389 2a.2 CameraSessionBuilder + ExifBuilder + 8 tests
0e97992 2a.1 PermissionsService + 9 tests
3570889 1.6 MediaStorage actor + 12 tests (failure matrix + race)
5fb3217 1.5 SessionAssignmentPolicy + 10 tests (haversine + boundaries)
8017d0f 1.4 FileOps + MediaFileSystem + 6 tests
a3795de 1.3 5 models with GRDB codecs
86cefba 1.2 Database + Migrations + 5 tests (CHECK, FK, CASCADE)
d3c6fed 1.1 GRDB SPM lockfile tracked
d0df54a 1.0 Storage + Concurrency ADR (12 항목)
```

**push 보류 유지 — rebuild/v2 origin 대비 +33 commits.**

---

## 8. 다음 단계

1. **실기기 manual checklist 수행** (§5) — 결과를 본 보고서에 누적 작성.
2. **Plan C 브레인스토밍 진입** — spec §11.1 결정 6항목 + Plan B gap (§6.4) 검토.
3. **push 결정** — manual checklist 완료 후 사용자 승인으로 `git push origin rebuild/v2`.
