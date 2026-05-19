# Camork — 전면 재구축 설계서 (v2)

- **작성일:** 2026-05-19
- **개정:** 2026-05-19 v2 — critic 피드백 반영 (스코프 축소, 보안 정교화, 누락 항목 추가)
- **상태:** 초안 — 사용자 리뷰 대기
- **상속 컨텍스트:** `/Users/jedel/Projects/CLAUDE.md`, `.claude/references/apple-hig.md`, `camork-ios/CLAUDE.md`

---

## 1. 정체성 (북극성)

업무용 카메라 앱 — 일반 사진/영상과 격리된 잠긴 로컬 앨범에 업무 자료를 촬영·보관.

**디자인 결정 우선순위 (북극성):**
1. **격리** — 업무 사진이 SNS/가족 사진과 절대 안 섞임.
2. **빠른 공유** — 격리되어 있되, 사용자가 의도하면 마찰 없이 외부로 보냄.
3. **보안** — 앱 진입 잠금으로 즉시·시각적 노출 차단.

**카피 정책:**
- 메인 카피·온보딩·App Store 설명: **"현장 기록"** 중심.
- "채증" 단어는 빠른 캡처 진입점(예: Lock Screen Widget의 라벨, v1.2에서 추가) 등 보조 표현에 한정. 법적·수사적 뉘앙스 부담 회피.

**범위:** 특정 산업 한정 X. 모든 산업의 업무 시나리오(현장 점검, 영업 증빙, 거래 기록, 자료 보관 등) 공통 적용.

## 2. 디바이스 / 플랫폼

- **iPhone 전용.** iPad 미지원.
- **iOS 17+** 디플로이먼트 타겟.
- **세로 모드 고정** (카메라 UX 세로 기준).
- **1차 언어 한국어**, 영어 번역 동봉.

## 3. 버전 스코프 (가장 중요한 변경)

이 spec은 **v1 Core**에 자세히 들어가고, v1.1 이후는 항목 단위로 명시한다.

### v1 Core — 출시 가능한 최소 (이 spec의 주된 작업 대상)
- 사진 촬영 (동영상 제외)
- 앱 샌드박스 내 격리 저장
- 자동 세션 묶음 + 수동 "새 현장"
- 현장 목록 / 현장 상세 / 사진 상세 (폴더 없음)
- 세션 메모 + 사진별 메모
- Face ID 앱 잠금 (잠금 = UI 진입 차단, 파일 암호화 아님)
- 공유 준비 화면 (텍스트·메타·EXIF 옵션 정리) → iOS Share Sheet 위임
- 한국어 + 영어

### v1.1 Workflow
- 폴더 (선택적 그룹)
- 세션 합치기 / 쪼개기 / 폴더 이동
- 검색 (세션명·메모·위치명)
- 시간 필터 (전체 / 7일 / 이번 달)
- 사후 편집 도구

### v1.2 Capture
- 동영상 + 사운드
- Lock Screen Widget ("빠른 채증" 라벨, Face ID 자동 인증)
- 지도 토글 (세션 위치 핀)

### v2 Trust
- iCloud Drive 옵션 암호화 백업 (별도 설계서 필요 — 키 관리, 복구, manifest, 분할 업로드)
- Control Center Control / Siri / Action Button / Camera Control API
- 다중 태그 (검색 강화)
- 리포트 PDF 생성

이하 4~10장은 **v1 Core** 기준으로 기술. v1.1 이상은 "추후 추가" 표기.

## 4. UX 흐름 (v1 Core)

### 4.1 메인 진입 — 카메라 우선

- 앱 열면 즉시 뷰파인더.
- 셔터 → 격리 앨범 자동 저장.
- 좌하단 작은 thumbnail = 직전 사진 (탭 시 사진 상세).
- 가운데 셔터.
- 우하단 카메라 전환 (전면/후면).
- 상단 좌측 잠금 아이콘 (`lock.fill` SF Symbol), 우측 갤러리 진입 (`square.grid.2x2` SF Symbol).
- 상단 가운데 작은 칩: **"새 현장"** + `plus.circle` (수동 세션 트리거).

### 4.2 셔터 후 흐름 — 자동 세션 + 수동 트리거

**자동 세션 분리 규칙:**
- 마지막 촬영으로부터 **GPS 50m 이상 이동** → 새 세션. **단, 위치 정확도(`horizontalAccuracy`)가 30m 초과면 거리 기반 분리는 적용하지 않음.**
- 마지막 촬영으로부터 **30분 이상 경과** → 새 세션.
- 위치 권한 없음 / 위치 비활성: 시간 규칙만 사용.
- 둘 다 아니면 → 같은 세션에 이어쓰기.

**수동 트리거 ("새 현장" 칩):**
- 다음 촬영부터 새 세션 적용 (즉시 빈 세션 만들지 않음).
- 사용자 의도가 분명하므로 자동 규칙보다 우선.

**자동 이름:**
- 기본: `M/d HH:mm 현장` (예: "5/19 14:30 현장")
- 역지오코딩 성공 시: `5/19 14:30 서울 강남구`
- 사용자가 언제든 변경 가능.

**v1 Core에서는 사후 합치기/쪼개기 없음** (v1.1).

### 4.3 갤러리 (v1 Core)

**구조:** 현장(세션) → 사진. 폴더 없음 (v1.1).

- "현장" 탭: 세션 카드 리스트, 시간순 역방향.
- 세션 카드:
  - 사진 미리보기 4장 그리드 (4번째에 "+N" 배지)
  - 세션명
  - 시간 · 위치명 · 사진 수
  - 우측: 공유 (`square.and.arrow.up`), 더보기 (`ellipsis.circle`)
- 세션 진입: 사진 그리드 + 세션명 편집 + 세션 메모 편집.
- 사진 진입: 단일 풀스크린 + 사진별 메모 편집 + 공유.

**v1 Core에서 없는 것:** 검색바, 시간 필터 칩, 지도 토글, "+" 폴더 생성 (모두 v1.1).

### 4.4 공유 (v1 Core)

**철학:** Camork는 "**무엇을** 공유할지"만 책임지고, "**어디로** 보낼지"는 iOS Share Sheet에 위임.

**공유 준비 화면 (Camork 커스텀 시트):**
- 사진 가로 썸네일 띠 (선택된 사진들)
- 자동 생성 텍스트 (편집 가능):
  - 형식: `[세션명] 시간 · 지역 — 사진 N장`
  - 위치 토글 OFF면 ` · 지역` 부분 제거
  - 시간 토글 OFF면 `시간` 부분 제거
- 메타 토글:
  - "위치 정보 포함" (기본 ON) — OFF 시 텍스트에서도 빠지고 EXIF에서도 위치 제거
  - "촬영 시간 포함" (기본 ON) — OFF 시 텍스트에서도 빠짐
- 하단: **"공유하기" 버튼** → `UIActivityViewController` 호출 (iOS Share Sheet)
- EXIF 제거가 필요한 경우 임시 폴더에 새 사본 생성 후 Share Sheet에 전달.

**v1 Core에서 없는 것:** 카카오톡·텔레그램 등 채널 직접 노출 (v2에서 안정성 검증 후 결정).

### 4.5 잠금

- 앱 시작 시 / 백그라운드에서 N분 후 복귀 시 잠금 화면.
- LocalAuthentication (`LAPolicy.deviceOwnerAuthenticationWithBiometrics` → 실패 시 `deviceOwnerAuthentication`로 패스코드).
- 잠금 정책 설정: 즉시 / 1분 / 5분 / 15분 / 끔.
- 잠금 화면 UI: 큰 카메라 아이콘 + "잠금 해제" 라벨. 진입 시 자동으로 Face ID prompt.
- Face ID 실패/취소 시: 잠금 화면 유지 (앱 화면 보이지 않음).

**중요한 한계 — 솔직하게 표기:**
- **잠금은 "앱 진입 UI 차단"이지 파일 자체 암호화가 아니다.** 기기가 잠금 해제된 상태로 USB 연결 + 디버그 모드 등 고급 공격에는 취약.
- 사용자에게는 "내 사진첩과 분리된 잠긴 앨범"이라고 정확히 표현. "절대 안전한 금고"라는 과장 카피 금지.

## 5. 데이터 / 저장소 / 보안

### 5.1 저장 위치

- **`Library/Application Support/Camork/Media/`** — 사진 본체. iCloud/iTunes 기기 백업에서 **제외** (`URLResourceKey.isExcludedFromBackup = true`).
  - 이유: 사용자가 "iCloud 백업으로 일반 클라우드에 갈 수 있다"는 오해를 차단. zero cloud 약속을 코드로 강제.
- **`Library/Application Support/Camork/Metadata/`** — SQLite (GRDB) 또는 JSON. 동일하게 백업 제외.
- **`Library/Caches/Camork/Thumbnails/`** — 썸네일 캐시. 백업 제외. 시스템이 공간 부족 시 자동 정리해도 무방하도록 재생성 가능 구조.
- **`tmp/Camork/Share/`** — 공유용 임시 사본 (EXIF 제거 등). 다음 항목 참조.

### 5.2 Data Protection class

- 모든 미디어 파일과 메타데이터: **`.completeUntilFirstUserAuthentication`**
  - 기기 부팅 후 사용자가 첫 잠금 해제하기 전까지 디스크에서 암호화 상태 유지.
  - 일반적 카메라 앱 수준의 디스크 보안.
- 더 엄격한 `.complete` (기기 잠겨있으면 접근 불가)는 미디어에 부적합 (백그라운드 저장 시 접근 필요). v2에서 옵션 고려.

### 5.3 백업·동기 정책 (Data Protection과 별개)

**3가지 백업 경로의 명확한 구분 (사용자에게도 설명):**

| 경로 | Camork v1 Core 정책 |
|---|---|
| **iTunes / Finder 기기 백업** | Camork 데이터 **제외** (`isExcludedFromBackup`) |
| **iCloud 백업** (시스템 백업) | Camork 데이터 **제외** (위와 동일 플래그) |
| **iCloud Drive** (앱별 컨테이너) | v1 Core **미사용**. v2에서 옵션으로 추가 예정 |
| **CloudKit 동기화** | v1 Core 미사용. v2 이후 고려 |

**결과:** v1 Core에서 사용자가 별도 행동을 안 하면 Camork 데이터는 **앱 샌드박스 내에만 존재하고 어디로도 자동 전송되지 않음**. 기기 분실 = 데이터 손실.

### 5.4 백그라운드 / 앱 전환 정책

- **앱 전환기(App Switcher) 스냅샷 가림:** 앱이 백그라운드 진입 시 즉시 카메라 세션 정지 + 메인 윈도우 위에 가림막(잠금 아이콘 또는 단색 view) 오버레이. 시스템이 캡처하는 스냅샷에 사진/뷰파인더 노출 X.
- **카메라 세션 정리:** `UIApplication.willResignActiveNotification` 시 `AVCaptureSession.stopRunning()`. 메모리·배터리·법적 노출 방지.
- **복귀 시:** 잠금 정책 위반(N분 경과) 시 잠금 화면 표시 후 통과해야 카메라 재진입.

### 5.5 공유 임시파일 수명

- EXIF 제거 등을 위해 만든 사본은 **`tmp/Camork/Share/<UUID>/`** 에 저장.
- Share Sheet가 닫힌 후 **즉시 정리** (`UIActivityViewController.completionWithItemsHandler`에서 삭제).
- 안전망: 앱 시작 시 `tmp/Camork/Share/` 내 24시간 이상 된 파일 청소.

### 5.6 삭제 / 휴지통 / 영구 삭제

- **휴지통(Trash) 도입** — 사진 삭제는 즉시 영구 삭제가 아니라 휴지통으로 이동 (메타 플래그 `deletedAt` 설정).
- 휴지통에서 30일 후 자동 영구 삭제 (백그라운드 정리 작업).
- 사용자가 휴지통에서 수동 영구 삭제 가능.
- 휴지통 비우기 시 디스크에서 파일 unlink + 가능하면 `freeRegion` 처리 (best-effort; 플래시 메모리에서 완전 wiping은 OS 책임).
- 세션 삭제 시: 그 세션의 모든 사진을 휴지통으로.

### 5.7 저장공간 관리

- 설정에 "저장공간 사용" 항목 — 총 사진 수, 디스크 사용량, 휴지통 사용량 표시.
- 임계점(예: 500MB 또는 1000장 누적) 도달 시 사용자에게 일회성 안내.
- 시스템 디스크 부족(`URLResourceKey.volumeAvailableCapacityForImportantUsageKey`) 감지 시 촬영 전 경고.

### 5.8 파일 명명 규칙

- 파일명: `<UUID>.heic` 또는 `<UUID>.jpg`. **민감 정보(시간·위치·메모) 파일명에 포함하지 않음.**
- 메타데이터는 모두 별도 DB/JSON에 저장.
- 이유: 휴지통/공유/외부 export 시 파일명 노출로 정보 새는 경로 차단.

### 5.9 앱 삭제 시

- iOS는 앱 삭제 시 앱 컨테이너(sandbox) 전체 제거 — Camork 데이터도 자동 삭제됨.
- 사용자에게 **앱 삭제 = 데이터 영구 삭제**임을 설정·온보딩에서 명시.
- v2의 iCloud Drive 백업이 들어가면 그 데이터는 별도 정책 필요 (현 단계 미해당).

## 6. 메타데이터 / 메모

### 6.1 자동 (모든 사진)
- 촬영 시각 (앱 시각 + 디바이스 EXIF)
- 위치 (CoreLocation, 권한 시) — 위·경도 + 역지오코딩 캐시(`placeName`) + `horizontalAccuracy`
- 디바이스 모델 / OS 버전 (감사·디버깅 목적)
- 카메라 설정 EXIF (ISO, 셔터, 조리개, 초점거리)

### 6.2 세션 단위
- 이름 (자동 → 사용자 변경)
- 메모 (선택, 자유 텍스트)

### 6.3 사진 단위
- 개별 메모 (선택)

### 6.4 메타 OFF 시 동작 (공유 시)
- 사진 EXIF에서 위치/시간 제거 (Image I/O로 새 복사본)
- 자동 텍스트에서도 해당 부분 제거
- 사용자 입력 메모는 그대로 (사용자 명시적 컨텐츠라 자동 제거 안 함)

### 6.5 사진 포맷 기본값
- **HEIC** 기본 (iOS 17+ 표준, 용량 효율).
- v1 Core 설정 옵션 없음. v1.1 이후 사용자 선택 가능(HEIC/JPEG).

## 7. 정보 구조 (v1 Core)

```
앱
├─ 카메라 (메인, 하단 탭 1)
│  ├─ 뷰파인더 + 셔터 + 카메라 전환 + 직전 사진 thumb
│  ├─ 상단: 잠금 / 갤러리 진입 / "새 현장" 칩
│  └─ 잠금 시 잠금 화면 오버레이
├─ 현장 (갤러리, 하단 탭 2)
│  ├─ 세션 카드 리스트 (시간순)
│  ├─ 세션 진입 → 사진 그리드 + 이름/메모 편집
│  └─ 사진 진입 → 단일 뷰 + 메모 편집 + 공유
└─ 설정 (하단 탭 3)
   ├─ 잠금 정책 (즉시 / 1·5·15분 / 끔)
   ├─ 권한 (카메라, 마이크[비활성, 동영상 v1.2], 위치)
   ├─ 언어 (한국어 / English)
   ├─ 저장공간 사용
   ├─ 휴지통
   ├─ 정보 / 개인정보처리방침 / 라이선스
   └─ 데이터 삭제 안내
```

**하단 탭:** 카메라 / 현장 / 설정 (3개).

## 8. 비주얼 톤

- **다크 모드 1차** — 카메라 정체성과 일치. 라이트 모드는 동등 검증.
- **모든 컬러는 semantic** — `Color(.systemBackground)`, `Color(.secondarySystemBackground)`, `.primary`, `.secondary`, `.tertiary` 등. 하드코딩 hex 금지.
- **액센트:** Asset Catalog의 `AccentColor`에 라이트/다크 변형으로 정의. 색상값은 frontend-design 단계에서 확정. 방향성은 "오렌지 계열(`Color.orange` 시스템 또는 변형)" — Halide/Sony α 톤 참조.
- **폰트:** 시스템 폰트(SF Pro → SD Gothic Neo 자동 fallback). 본문은 시스템, 브랜드 헤더 적용 여부는 frontend-design 단계에서.
- **아이콘:** 모든 UI 아이콘은 **SF Symbols**. emoji 기호(`📷`, `🗺`, `▶`) 사용 금지 — spec과 코드 모두에서 정확한 SF Symbol 이름으로 표기.
- 정확한 hex / 폰트 weight 매핑 / 모션 토큰: 후속 frontend-design 단계에서 토큰화.

## 9. 아키텍처 (v1 Core)

### 9.1 모듈 구조

```
Camork/
├─ CamorkApp.swift            — App entry
├─ AppLock/                   — Face ID 잠금, 백그라운드 가림막, 잠금 정책
├─ Camera/                    — AVFoundation 캡처 (사진만, v1 Core)
│  ├─ CameraSession.swift
│  ├─ CameraView.swift        — UIViewControllerRepresentable
│  ├─ ShutterController.swift
│  └─ MediaCapture.swift
├─ Sessions/                  — 도메인 모델 + 자동 묶기
│  ├─ Session.swift
│  ├─ SessionManager.swift    — 자동 분리 규칙, 수동 트리거, accuracy 가드
│  └─ SessionStore.swift      — 영속
├─ Storage/                   — 로컬 파일 / 메타데이터
│  ├─ MediaStorage.swift      — Application Support/Media/, isExcludedFromBackup
│  ├─ MetadataStore.swift     — SQLite (GRDB) 또는 JSON
│  ├─ Thumbnails.swift        — 캐시 관리
│  ├─ Trash.swift             — 휴지통 모델 + 30일 자동 정리
│  └─ TempCleanup.swift       — tmp/Share/ 청소
├─ Gallery/                   — UI (v1 Core: 세션 리스트, 세션/사진 상세)
│  ├─ SessionListView.swift
│  ├─ SessionDetailView.swift
│  └─ PhotoDetailView.swift
├─ Share/                     — Camork 공유 준비 + Share Sheet 위임
│  ├─ ShareSheetView.swift
│  ├─ ShareComposer.swift     — 자동 텍스트, EXIF 처리, 임시파일 생성
│  └─ ExifSanitizer.swift     — Image I/O로 메타 제거 사본
├─ Settings/
│  └─ SettingsView.swift
├─ Services/
│  ├─ LocationService.swift
│  └─ PermissionsService.swift
├─ DesignSystem/
│  ├─ Theme.swift             — semantic color 매핑, 토큰
│  └─ Components/             — 통일 컴포넌트
└─ Resources/
   ├─ Assets.xcassets         — AccentColor (라이트/다크), 앱 아이콘
   └─ Localizable.xcstrings   — 한국어 1차, 영어 번역
```

**v1.1+ 추가 시:** `Folders/`, `Search/`, `MapView/`, `Edit/`(세션 편집)
**v1.2+ 추가 시:** `Video/`, `Widgets/` (별도 타겟)
**v2+ 추가 시:** `Backup/`, `Encryption/`

**원칙:** 각 모듈은 독립 컴파일 가능한 단위. 추후 SwiftPM 로컬 패키지로 분리 가능한 구조.

### 9.2 데이터 모델 (v1 Core)

```swift
struct Session: Identifiable, Codable {
    let id: UUID
    var name: String
    var note: String?
    var createdAt: Date
    var endedAt: Date?
    var location: LocationSnapshot?   // 세션 첫 사진 위치
    var photoIds: [UUID]
    // folderId는 v1.1에서 추가. 추가 시 단일 source of truth.
}

struct Photo: Identifiable, Codable {
    let id: UUID
    let fileURL: URL                  // <UUID>.heic
    let thumbnailURL: URL?            // 캐시 경로 (재생성 가능)
    let kind: MediaKind               // .photo (v1 Core), .video (v1.2)
    let capturedAt: Date
    let location: LocationSnapshot?
    let exif: ExifData?
    var note: String?
    var deletedAt: Date?              // 휴지통 플래그
}

struct LocationSnapshot: Codable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let placeName: String?
}
```

**v1.1 추가 시 `Folder` 모델 도입. `Session.folderId: UUID?` 단일 필드가 source of truth. 역방향 조회는 query로.**

### 9.3 데이터 흐름

**촬영:**
```
사용자 셔터 탭
→ Camera/MediaCapture: AVCapturePhotoOutput.capturePhoto()
→ MediaStorage: <UUID>.heic 저장 (Application Support/Media/, backup 제외)
→ Photo 모델 생성 + LocationService 스냅샷 + EXIF
→ SessionManager.assignToCurrent(photo):
    ├ 위치 권한 + horizontalAccuracy ≤ 30m: 거리 규칙 적용
    └ 외: 시간 규칙만
→ SessionStore.persist()
→ Thumbnail 생성 + 캐시
→ UI: 뷰파인더 thumb 갱신
```

**갤러리 로드:**
```
"현장" 탭 진입
→ SessionStore.fetch(.notDeleted, sortedByCreatedAt: .descending)
→ LazyVStack 표시
```

**공유:**
```
세션 카드 공유 탭
→ ShareSheetView (sheet detents .medium / .large)
→ ShareComposer:
    ├ 자동 텍스트 생성 (메타 토글 반영)
    ├ 메타 OFF: ExifSanitizer로 tmp/Share/<UUID>/ 에 정제 사본
    └ 사용자 "공유하기" 탭 → UIActivityViewController(items: [텍스트] + [사진 URL들])
→ Share Sheet 닫힘 → tmp/Share/<UUID>/ 즉시 삭제
```

### 9.4 동시성

- `actor SessionManager` — 세션 상태 race condition 방지
- `actor MediaStorage` — 디스크 쓰기 순서 보장
- UI: `@MainActor`
- AVFoundation 캡처: 백그라운드 큐(Apple 권장)

## 10. 에러 처리 (v1 Core)

| 상황 | 동작 |
|---|---|
| 카메라 권한 거부 | 빈 화면 + "카메라 권한 필요" + 설정 deeplink |
| 위치 권한 거부 | 정상 동작, 위치 메타데이터 없이 시간 기반 세션만 |
| Face ID 실패/취소 | 잠금 화면 유지, 앱 컨텐츠 노출 X |
| 저장공간 부족 (촬영 전) | 경고 + "정리하기" 안내, 휴지통 비우기 권유 |
| 저장공간 부족 (촬영 중) | 최대한 저장 시도, 실패 시 사용자에게 에러 토스트 |
| AVFoundation 초기화 실패 | 재시도 1회 → 실패 시 에러 화면 + 보고 옵션 |
| 백그라운드 진입 | 카메라 세션 정지 + 가림막 + 메모리 해제 |
| 잠긴 상태에서 Share extension 트리거 | iOS 시스템 차단 (앱이 잠겨있어 접근 불가, 정상) |
| 메타데이터 DB 손상 | 로컬 백업 자동 복원 시도 → 실패 시 사용자 안내 + 새 DB로 재시작 |
| 휴지통 영구 정리 시 파일 누락 | best-effort, 메타 record만 정리 |

## 11. 테스트 전략 (v1 Core)

### 11.1 Unit (Swift Testing `@Test`)
- `SessionManager`:
  - GPS 49m/50m/51m 경계
  - 시간 29분/30분/31분 경계
  - `horizontalAccuracy` 25/30/35m 경계 — 거리 규칙 활성/비활성
  - 위치 권한 없음 — 시간만 적용
  - 수동 트리거 후 다음 촬영부터 적용
- `MediaStorage`: 파일 명명, `isExcludedFromBackup` 플래그 검증, 동시 쓰기 순서
- `MetadataStore`: 영속·로드·스키마 v1→v2 마이그레이션 시나리오
- `Trash`: 30일 경과 시 자동 삭제, 휴지통 비우기, 휴지통 사진의 갤러리 필터링
- `ShareComposer`: 자동 텍스트 형식, 메타 OFF 시 텍스트 변경
- `ExifSanitizer`: 위치/시간 제거 후 EXIF 검증
- `TempCleanup`: 24시간 경과 임시파일 청소

### 11.2 Integration
- 카메라 캡처 → 저장 → 세션 할당 → 갤러리 표시 전체 파이프라인
- 잠금: 백그라운드 → N분 → 복귀 → Face ID → 진입 시간 측정 (< 2초)
- 공유: 메타 OFF → 임시파일 생성 → Share Sheet → 닫힘 → tmp 정리

### 11.3 UI / 수동 검증
- SwiftUI `#Preview` light / dark
- Dynamic Type AX5에서 안 깨짐
- VoiceOver 라벨 전체 인터랙티브 요소
- 한국어 / 영어 텍스트 잘림 없음
- 권한 거부 시나리오 3종 (카메라/위치/마이크[v1.2])
- App Switcher 스냅샷에 사진/뷰파인더 안 보임 확인
- 다양한 GPS 정확도 시뮬레이션 (Xcode Location Simulator)

## 12. 성능 기준 (v1 Core)

- **앱 콜드 스타트 → 카메라 활성:** < 1.5초 (최신 기기 기준)
- **셔터 탭 → 다음 컷 준비:** < 0.5초
- **갤러리 진입 → 첫 화면:** < 0.3초 (세션 500개까지)
- **세션 500개 / 사진 5,000장 누적 시:** 갤러리 스크롤 60fps 유지
- **메모리:** 카메라 활성 시 < 200MB
- **위 기준을 넘으면 v1 출시 보류 사유.**

## 13. 1차 출시 (v1 Core) 체크리스트

**App Store 출시 준비:**
- [ ] 모든 권한 plist 문구 한국어 + 영어 (`NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription`, `NSFaceIDUsageDescription`)
- [ ] 개인정보처리방침 (한/영) — 저장 위치, 백업 제외 명시, 위치 사용 명시
- [ ] App Store 스크린샷 (다크 모드 기준 5장)
- [ ] App Store 설명 (한/영) — "현장 기록" 중심 카피
- [ ] 1.0.0 버전, Build 1
- [ ] Bundle ID `com.camork.app` (기존 유지)
- [ ] App Icon (라이트/다크/틴티드 iOS 18+ 지원)
- [ ] Universal Links / URL Scheme 없음 (v1 Core)

## 14. 마이그레이션

- 기존 Camork 코드: **참고용**. 새 아키텍처로 처음부터.
- 기존 사용자 데이터: 없음 (출시 전 재구축).
- `agent-office/`: 본체와 분리 유지, 빌드 파이프라인 제외.
- `project.yml` 잔재 정리: `UISupportedInterfaceOrientations~ipad` 제거.

## 15. 오픈 이슈 (writing-plans 단계에서 결정)

- 메타데이터 영속 방식: SQLite(GRDB) vs JSON 파일 (선택 트리거: 사진 수 1만 이상 시 검색/필터 성능)
- 액센트 컬러 정확한 값 (Asset Catalog에서 frontend-design이 정함)
- 폰트 weight 매핑 (헤더에 Pretendard 도입 여부)
- 휴지통 30일 기준: 절대일 vs 사용자 설정 가능
- 잠금 N분 기본값 (즉시 / 1분 / 5분 중 디폴트)
- App Switcher 가림막 디자인 (단색 / 잠금 아이콘 / 로고)
- 위치 권한 요청 시점 (앱 첫 실행 vs 첫 촬영 vs 설정에서 명시적)
- 휴지통 진입 위치 (설정 → 휴지통 vs "현장" 탭 상단 액션)
- 사진 상세 화면의 줌·팬 동작 정의
- 동영상(v1.2) 사양 — 코덱, 최대 길이, 압축
- **v1 Core 출시 자산 전부 새로 작성** (기존 자산 모두 삭제됨): `privacy.html` (한/영, v1 Core 스코프 = 사진만·마이크 미사용에 맞춤), App Store 설명/스크린샷, `project.yml` + `Camork.xcodeproj` (XcodeGen 재생성), App Icon (라이트/다크/틴티드)

---

## 다음 단계

1. **사용자 리뷰** — 본 v2가 위 critic 우려를 충분히 반영했는지 확인.
2. **승인 후** — `superpowers:writing-plans` 스킬로 v1 Core 구현 계획 (phase 별 / 파일 별 / 검증 단계 포함) 작성.
3. **그 다음** — TDD 기반 모듈 단위 구현.

## 부록: critic 피드백 반영 매핑

| critic 지적 | v2 반영 위치 |
|---|---|
| 스코프 과대 | §3 버전 분할, 이후 모든 장은 v1 Core 기준 |
| iCloud 백업 별도 제품 | §3에서 v2로 이동, §5.3 백업 표 |
| 보안 표현 위험 | §4.5 "한계 솔직 표기" + §5.2 Data Protection class 명시 |
| 공유 채널 직접 노출 리스크 | §4.4 "공유 준비 화면 → iOS Share Sheet 위임" |
| 세션/폴더 모델 충돌 | §9.2 — `Session.folderId` 단일 source of truth (v1.1) |
| 자동 세션 GPS accuracy 누락 | §4.2 — `horizontalAccuracy ≤ 30m` 가드 |
| 비주얼 hex 명시 충돌 | §8 — semantic color 기반 표현 |
| emoji → SF Symbols | §8 + 본문 전반 (`square.and.arrow.up` 등) |
| 휴지통/영구삭제 누락 | §5.6 추가 |
| 저장공간 관리 누락 | §5.7 추가 |
| 썸네일 캐시 보안 | §5.1 + §11.1 추가 |
| 임시파일 수명 | §5.5 추가 |
| 백그라운드 카메라 정지 | §5.4 추가 |
| 파일명 민감정보 금지 | §5.8 추가 |
| 대량 성능 기준 | §12 추가 |
| 사진 포맷 기본값 | §6.5 — HEIC 기본 |
| 메타 OFF 시 텍스트 처리 | §6.4 명시 |
| "채증" 단어 정책 | §1 카피 정책 — 메인은 "현장 기록" |
