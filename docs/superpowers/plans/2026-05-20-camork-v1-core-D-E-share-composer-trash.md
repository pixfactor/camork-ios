# Plan D + E execution plan — Share Composer + Trash/AppLock/Settings

- **작성일:** 2026-05-20
- **브랜치:** rebuild/v2 (push 후 2a23b18 base에서 진행)
- **상위 spec:** `docs/superpowers/specs/2026-05-19-camork-rebuild-design.md` §4.4 / §4.5 / §5.6 / §5.7
- **선행:** Plan C 완료 보고서 (`reports/2026-05-19-plan-C-gallery-share-complete.md`) §5–6 인계 항목

---

## 1. Scope 결정

Plan D/E 전체를 한 batch로 묶으면 risk 큼. Plan C 보고서의 인계 항목 + master spec §4.4/§4.5/§5.6 을 다음과 같이 **batch 단위**로 쪼갠다. Plan D를 우선 닫고 E는 별도 검증.

### Plan D — Share Composer full UX

| Batch | 내용 | 의존성 |
|---|---|---|
| **D1** | 옵션 sheet 안에서 자동 텍스트를 편집 가능하게 (TextField + override 경로) | none |
| **D2** | PhotoDetailView 단일 사진 share 진입점 — SessionDetailScreen에서 session을 PhotoDetailView로 전달 | none (D1과 독립) |
| **D3** | 옵션 sheet 안 사진 가로 thumbnail 띠 (master spec §4.4) | D1 |
| **D4** (stretch) | 토글 변경 시 사용자가 편집 안 한 자동 텍스트만 live regenerate | D1 |

### Plan E — Trash / AppLock / Settings

| Batch | 내용 | 의존성 |
|---|---|---|
| **E1** | Trash viewer — `fetchDeletedPhotos` / `fetchDeletedSessions` query + 복원/영구삭제 | none |
| **E2** | Delete action UI (sheet button) — E1 viewer가 존재해야 비로소 노출 (stranded 위험 해소) | E1 |
| **E3** | AppLock — LocalAuthentication + scenePhase background timer | none (D와 독립) |
| **E4** | Settings 화면 — Lock policy picker · Trash 진입 · AccentColor placeholder · About | E1+E3 |
| **E5** (stretch) | 30일 영구 삭제 background task | E1 |

---

## 2. 본 plan에서 명확히 out-of-scope

- 채널별 직접 노출 (KakaoTalk/Telegram SDK) — v2 영역 (master spec §4.4)
- iCloud Drive / CloudKit — v2 영역 (master spec §5.3)
- Swift 6 strict concurrency 전환 — 별도 작업
- 진짜 AccentColor final hex — 디자이너 입력 대기 (Plan C open question)

---

## 3. Batch별 exit criteria

각 batch는 다음을 만족해야 commit + 다음 batch 진입 허용.

1. `xcodegen generate` 정상 생성 (project.yml 변경 시).
2. `xcodebuild test -project Camork.xcodeproj -scheme Camork -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO` 그린.
3. Test 수 회귀 없음 + 새 영역마다 단위 테스트 1+ 추가.
4. Lore protocol commit (OmX coauthor) — Constraint / Rejected / Confidence / Scope-risk / Directive / Tested / Not-tested 명시.
5. `/Users/jedel/Desktop/camork-implementation-notes.html` 갱신 — 의미 있는 decision/tradeoff 발생 시 entry 추가 + 헤더 + footer 동기화 (이전 세션 사용자 지시).

---

## 4. Batch D1 — 편집 가능한 share auto-text

### 4.1 변경 파일

- `Camork/Share/SharePreparer.swift` — `prepare(...)`에 `overrideText: String?` 파라미터 추가. nil이면 기존 autoText 사용, 비-nil이면 사용자가 편집한 텍스트를 그대로 ShareBundle.autoText에 사용.
- `Camork/Share/ShareEntryButton.swift` — 옵션 sheet에 `TextEditor` 추가 (또는 `TextField` multi-line). 초기 값은 합성된 autoText preview. 사용자가 편집하면 `customText` state에 보관. Share 누를 때 `overrideText: customText` 전달.
- `Camork/Resources/Localizable.xcstrings` — `share_options_text_label` / `share_options_text_placeholder` 추가 (한·영).

### 4.2 변경 안 함

- `ShareSanitizer` — 텍스트와 무관.
- `SharePreparer.autoText` private 함수 — 그대로 preview 생성용.

### 4.3 단위 테스트 (`CamorkTests/SharePreparerTests.swift`)

신규:
- `overrideText nil → 기존 autoText 동작` (regression guard)
- `overrideText 빈 문자열 → ShareBundle.autoText는 빈 문자열` (의도적 사용자 선택 보존)
- `overrideText "내가 쓴 메모" → ShareBundle.autoText 그대로 반영` (passthrough 검증)
- `overrideText 사용 시 location/time 토글이 무의미해도 sanitizer 결과(GPS strip)는 토글 따름` (텍스트와 메타 정책 분리)

### 4.4 Exit criteria

- 기존 4 variants 테스트 통과 (regression).
- 새 4 케이스 통과.
- ShareEntryButton 옵션 sheet에서 TextEditor 보이고 placeholder/label 정상.

---

## 5. Batch D2 — PhotoDetail 단일 사진 share

### 5.1 변경 파일

- `Camork/Gallery/SessionDetailScreen.swift` — `SessionPhotoDetailItem`에 session 정보 포함 (또는 PhotoDetailView init에 session 전달). DependencyContainer에서 SharePreparer를 PhotoDetailView로 전달.
- `Camork/Gallery/PhotoDetailView.swift` — init에 `session: Session`, `sharePreparer: SharePreparer` 추가. topBar에 ShareEntryButton(`session: session, photos: [photo], sharePreparer: sharePreparer`) 노출.
- `Camork/Resources/Localizable.xcstrings` — `photo_detail_share_a11y` 추가.

### 5.2 변경 안 함

- `ShareEntryButton` API — 이미 `photos: [Photo]`라서 단일 사진 array 그대로 작동.
- `SharePreparer.prepare` — `[Photo]` iterate 그대로 작동.

### 5.3 단위 테스트

- `SharePreparerTests`에 `singlePhotoFromPhotoDetail` (이미 multiplePhotos 케이스가 있어 단일 1장은 사실상 기존 `singlePhotoBothOn`와 동일 — neutral case).
- UI 단위 테스트는 SwiftUI sheet라 skip (보고서 §6 정책과 일치).

### 5.4 Exit criteria

- PhotoDetailView가 session 없이 컴파일 깨지지 않음 (preview / SessionDetailScreen 양쪽 호출자 갱신).
- 단일 사진 share flow end-to-end (시뮬레이터 build).

---

## 6. Batch D3 — Composer 사진 thumbnail 띠

### 6.1 변경 파일

- `Camork/Share/ShareEntryButton.swift` — 옵션 sheet 상단에 `LazyHStack` of `ThumbnailView(photo:)`로 thumbnail strip.
- Reuse 기존 `ThumbnailView` (Gallery용) — `Camork/Gallery/ThumbnailView.swift`.

### 6.2 Exit criteria

- 다중 사진 share 시 카드 형태로 가로 띠 표시.
- 한 장이면 single tile (또는 hide).

---

## 7. Batch D4 (stretch) — Live regenerate auto-text

토글 변경 시 자동 텍스트가 갱신되어야 하지만 사용자가 편집한 상태면 덮어쓰지 않음.

### 7.1 핵심 결정

- `customText`를 `String?`로 두고, 사용자가 한 번이라도 편집하면 non-nil로 stick.
- 토글 변경 시 nil인 상태에서만 새 합성으로 update.

### 7.2 Exit criteria

- 토글 ON/OFF 반복 시 텍스트 미리보기 일관.
- 사용자가 편집 후 토글 변경해도 편집 보존.

---

## 8. Plan E batch들 (요약만, 실제 실행은 Plan D 완료 후 별도 plan refine)

### E1 — Trash viewer

- `MediaStorage` 신규 query — `fetchDeletedPhotos(ascending capturedAt)` / `fetchDeletedSessions(ascending deletedAt)`.
- 신규 화면 `TrashScreen` — 세션 단위 그룹 + 사진 grid.
- 복원 action — `MediaStorage.restorePhoto(id:)` / `restoreSession(id:)`. soft-delete 컬럼을 nil로.
- 영구 삭제 — `MediaStorage.purgePhoto(id:)` (final 파일 unlink + thumb cache unlink + DB DELETE).

### E2 — Delete action UI

- SessionDetailScreen 사진 카드 long-press 메뉴에 "휴지통으로 이동".
- 세션 toolbar에 "세션 삭제" (모든 사진 휴지통으로).
- E1 viewer가 있어야 user trapping 없음.

### E3 — AppLock

- 신규 actor `AppLockController` — LocalAuthentication 호출 + lock policy 보유 (UserDefaults persist).
- ScenePhase `.background` 진입 시간을 기록 → `.active` 전환 시 경과 시간 > policy → 잠금 ON.
- 잠금 화면 = 큰 Camork 아이콘 + "잠금 해제" 버튼 → Face ID prompt.

### E4 — Settings 화면

- `SettingsScreen` replaces `SettingsPlaceholderView`.
- 항목: Lock policy picker · Trash 진입 · "About Camork" (버전/Privacy Policy/Terms).
- AccentColor final hex은 별도 UI 작업.

### E5 (stretch) — 30일 background purge

- `MediaStorage.purgeExpired(cutoff:)` — `deletedAt < cutoff`인 row + 파일 제거.
- 앱 시작 시 best-effort 호출 (현재 `runReaper`와 같은 패턴). BGTaskScheduler는 v1 Core 미사용 (Plan E에서 결정).

---

## 9. 진행 순서 + 의사 결정 정책

1. 본 plan doc commit.
2. D1 → 테스트 그린 + commit → HTML 갱신.
3. D2 → 테스트 그린 + commit → HTML 갱신.
4. D3 → 테스트 그린 + commit → HTML 갱신.
5. D4 (선택) → 테스트 그린 + commit → HTML 갱신.
6. **여기서 일시 정지** — Plan D 결과를 사용자 검토 받은 뒤 Plan E refine + 실행.

각 batch는 commit 단위로 분리. Lore protocol + OmX 공저. push는 없음. TestFlight upload도 없음. 실기기 manual 검증 항목은 batch별 "Not-tested" 라인에 누적.
