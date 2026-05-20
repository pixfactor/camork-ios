# Plan C 완료 보고서 — Gallery + Share v1

- **작성일:** 2026-05-20
- **브랜치:** rebuild/v2 (본 보고서 커밋 포함 origin 대비 +57 commits, push 보류)
- **마스터 spec:** `docs/superpowers/specs/2026-05-19-camork-rebuild-design.md`
- **Plan C spec:** `docs/superpowers/specs/2026-05-19-camork-v1-core-C-gallery-design.md`
- **Plan C plan:** `docs/superpowers/plans/2026-05-19-camork-v1-core-C-gallery-share.md`

---

## 1. 산출 phase × commit 매핑

| Phase | 내용 | Commit |
|---|---|---|
| Planning | Plan C scope/spec/plan 정렬 | `87fe04e`, `89f9573`, `d04d339` |
| 1.1 | Gallery query API (`fetchSessions`, `fetchPhotos`) | `c7cbae9` |
| 1.2 | Session preview packaging, N+1 회피 | `a3e6add` |
| 1.3 | Session name/note edit domain wrapper | `12486bd` |
| 1.4 | `fetchPhoto` soft-delete guard | `3d267e7` |
| 2.1 | Thumbnail cache file ops + caches root | `237360d` |
| 2.2 | ImageIO thumbnail generator | `aed8d01` |
| 2.3 | Thumbnail coordinator bounded/coalesced generation | `fc9149a`, `cf19ebd`, `57ec396` |
| 3.1 | Gallery loading state | `9e5e1a3` |
| 3.2 | Session cards + thumbnail lifecycle | `76dae6a`, `5db3c6f` |
| 3.3 | Session detail grid | `31ba8dd` |
| 3.4 | Session edit sheets | `593c99b` |
| 3.5 | Gallery tab exposure | `8fd4ee8` |
| 4.1 | ShareSanitizer | `879a843` |
| 4.2 | SharePreparer actor | `3ac94a4` |
| 4.3 | UIActivityViewController wrapper | `41f1093` |
| 4.4 | ShareEntryButton + localization + toolbar wiring | `6fb08c2` |
| 4.5 | DependencyContainer sharePreparer + startup cleanup | `0117ac9` |

**Plan C 구현 커밋:** 23개 (`87fe04e..0117ac9`).
**누적 테스트:** Plan B 90 → Plan C 완료 135 tests / 20 suites.

---

## 2. 검증 결과

### 2.1 Clean build + 전체 회귀

```bash
xcodegen generate
xcodebuild clean -project Camork.xcodeproj -scheme Camork
xcodebuild test -project Camork.xcodeproj -scheme Camork \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

**결과:**
- `xcodegen generate` → SUCCEEDED
- `xcodebuild clean` → **CLEAN SUCCEEDED**
- `xcodebuild test` → **TEST SUCCEEDED**
- **135 tests in 20 suites passed**
- 0 test failures / 0 compiler errors
- xcresult: `/Users/jedel/Library/Developer/Xcode/DerivedData/Camork-aasektavvixxksceeiiyujbjwvcr/Logs/Test/Test-Camork-2026.05.20_13-44-17-+0900.xcresult`

### 2.2 Static / resource checks

```bash
git diff --check
jq empty Camork/Resources/Localizable.xcstrings
```

**결과:** 둘 다 exit 0. Whitespace error 없음, xcstrings JSON 유효.

### 2.3 Suite 증가 요약

Plan C에서 추가/확장된 주요 검증:

- Gallery query / preview / soft-delete filtering: `MediaStorage`
- Session edit: `SessionNameEditor`, `SessionNoteEditor`
- Thumbnail cache: `MediaFileSystem`, `ThumbnailGenerator`, `ThumbnailCoordinator`
- Share metadata: `ShareSanitizer`, `SharePreparer`

---

## 3. Corrective pass 기록

### 3.1 Thumbnail phase 보강

- Thumbnail read/write는 `Library/Caches/Camork/Thumbnails/`를 기준으로 고정.
- orphan reaper가 legitimate thumbnail을 지우지 않도록 photo row와 파일명을 함께 검증.
- 동일 photo의 cache miss는 하나의 generator call로 coalesce, distinct miss는 concurrency limit 4로 bounded.

### 3.2 ShareSanitizer 보강

초기 구현에서 `CGImageDestinationCopyImageSource` 경로가 orientation / DateTimeOriginal 보존에 취약했다. 최종 구현은 `CGImageDestinationAddImageFromSource` 기반으로 원본 프레임을 복사하고, GPS dictionary 제거와 XMP GPS tag 제거를 명시 수행한다.

보존 검증:
- orientation
- ICC color profile
- DateTimeOriginal

제거 검증:
- EXIF GPS dictionary
- XMP GPS metadata

### 3.3 Share UI/DI 보강

- share button은 세션 상세 화면의 이미 로드된 `photos`를 사용한다. 세션 카드는 preview photo만 보유하므로 card-level share는 아직 연결하지 않았다.
- `SharePreparer`는 `DependencyContainer`가 보유한다. SwiftUI View가 actor를 임시 생성하지 않게 하여 lifecycle과 cleanup 책임을 앱 DI 경계에 고정했다.
- 앱 시작 시 `cleanupExpired()`를 best-effort로 실행하고, share sheet completion에서 해당 bundle temp dir을 즉시 삭제한다.

---

## 4. 실기기 manual 결과

**상태:** 미실행. 현재 검증은 iPhone 17 Pro simulator의 build/test 회귀까지 완료했다. 실제 카메라, 실제 share target 앱, iOS 파일 컨테이너 확인은 실기기에서 닫아야 한다.

### 4.1 Gallery / Session detail

- [ ] 촬영 후 Gallery 탭에 세션 카드가 최신순으로 표시
- [ ] 세션 카드 preview 4장 + `+N` 배지 표시
- [ ] 세션 진입 → 정사각형 grid 표시
- [ ] 세션명 편집 sheet 저장/취소
- [ ] 세션 메모 편집 sheet 저장/삭제/취소
- [ ] PhotoDetailView 재진입 시 메모 유지

### 4.2 Thumbnail / 성능

- [ ] 최초 진입 시 thumbnail 생성 후 재진입 cache hit 체감
- [ ] 빠른 스크롤 시 UI hang 없음
- [ ] 동일 이미지 다중 요청에서 중복 생성 체감 없음

### 4.3 Share v1 lite

- [ ] 공유 버튼 → 공유 옵션 sheet 표시
- [ ] 위치 OFF → 수신 파일의 GPS metadata 없음
- [ ] 위치 ON → GPS metadata 보존
- [ ] 시간 OFF/ON → 자동 텍스트에서 시간 포함 여부 반영
- [ ] 공유 sheet 닫힘 → `tmp/Camork/Share/<UUID>/` 삭제
- [ ] KakaoTalk/Telegram 등 설치 앱 공유 시 사진 + 자동 텍스트 전달 확인
- [ ] 앱 재시작 시 24h 이상 share temp orphan cleanup

### 4.4 Visual / accessibility

- [ ] 다크/라이트 모두 정상
- [ ] Dynamic Type AX5에서 gallery/detail/share sheet 깨짐 없음
- [ ] VoiceOver: gallery card, edit, share, close label 명확
- [ ] 한국어/영어 모두 잘림 없음

---

## 5. Plan D / Plan E 인계

### 5.1 Plan D — ShareComposer full UX

Plan C가 제공한 재사용 인프라:

- `ShareSanitizer`
- `SharePreparer`
- `ShareSheetController`
- `ShareEntryButton`

Plan D에서 결정할 항목:

- 사전 미리보기 화면에서 자동 텍스트를 편집 가능하게 할지
- 사진별 메타 옵션을 개별 제어할지, 세션 단위 토글만 유지할지
- Camork 자체 channel ranking/preselect를 둘지, 계속 iOS share sheet 위임으로 단순화할지
- placeName fallback이 없을 때 좌표를 텍스트에 넣을지, 생략할지
- share localization final copy

### 5.2 Plan E — Trash / AppLock / Settings

Plan C가 제공한 재사용 인프라:

- `deletedAt IS NULL` query-level filtering
- soft-deleted photo/session이 detail/share/fetch 경계에 노출되지 않는 테스트 기반
- Gallery tab 구조와 detail routing

Plan E에서 결정할 항목:

- Trash viewer UI와 복원/영구삭제 flow
- delete action 노출 시점. 현재 Plan C에서는 viewer 부재로 항목 stranded 위험이 있어 delete UI 미노출
- AppLock 상태에서 gallery/share 접근 차단 UX
- Settings 화면 진입점, AccentColor final hex, App Icon, 영문 copy polish

---

## 6. 미해결 / gap

- **실기기 manual 미완료:** 카메라 capture, 실제 share target 앱, filesystem inspection은 기기 필요.
- **세션 카드 share 미연결:** card는 preview만 들고 있어 full session share를 위해 추가 fetch 정책이 필요. 현재는 SessionDetail toolbar에서 전체 사진 공유.
- **PhotoDetail 개별 share 미연결:** Plan C lite는 세션 단위 공유만 닫았다. 개별 사진 공유는 Plan D에서 UX와 함께 결정.
- **ShareEntryButton UI 테스트 없음:** SwiftUI sheet / `UIActivityViewController` interaction은 build + manual 검증 영역.
- **Swift 6 전환 미수행:** 현재 `swift-version 5` 유지. Swift 6 strict concurrency 전환은 별도 작업.
