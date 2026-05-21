# Camork 수정 내역 — Build 15 (rebuild/v2)

> 2026-05-21 세션 작업 정리

## 1. 갤러리 하단 fade — 카드가 tab bar capsule 영역에서 자연스럽게 사라지도록

**파일**: `Camork/Camork/Gallery/GalleryScreen.swift`, `Camork/Camork/RootTabView.swift`

### 변경 과정
1. **`.toolbarBackground(.ultraThinMaterial, for: .tabBar)` + `.toolbarBackground(.visible, for: .tabBar)` 제거** — 강제 visible 모드가 컨텐츠를 capsule 위에서 잘라내고 있었음
2. **`.safeAreaInset(edge: .bottom)` 제거** — 추가 inset이 fade 공간을 좁힘
3. **`List` → `ScrollView + LazyVStack` 전환** — List는 `.mask` 동작 보장이 약함
4. **`.contentMargins(.bottom, 0, for: .scrollContent)`** — 시스템 자동 inset 무력화, 컨텐츠가 capsule 영역으로 흘러 들어감
5. **`.ignoresSafeArea(edges: .bottom)`** — ScrollView frame을 화면 끝까지 확장
6. **`.overlay(alignment: .bottom)` 로 `Color(.systemBackground)` opacity 0 → 1 그라데이션 160pt** — 카드를 색으로 덮어 fade-out
7. **RootTabView의 색 기반 `bottomChromeFade` 와 `GalleryBottomChromeFadePreferenceKey` 제거** (무용지물)

### 시도했다가 폐기한 방향
- 색 그라데이션 0.65 opacity (RootTabView overlay) — 색 차이가 작아 dark/light 모두 안 보임
- `.mask(VStack { gradient + Color.black + gradient })` — List에 적용 시 동작 안 함, large title 가림
- 상단 fade overlay 32pt — large title 가림 + navigation bar 자체 fade와 충돌해 검은 띠

## 2. SessionDetailScreen 하단 fade — 갤러리와 동일 패턴

**파일**: `Camork/Camork/Gallery/SessionDetailScreen.swift`

- ScrollView에 `.scrollIndicators(.hidden)`, `.contentMargins(.bottom, 0, ...)`, `.ignoresSafeArea(edges: .bottom)`, bottom overlay 160pt 추가
- 상단 fade는 검은 띠 문제로 제거

## 3. PhotoDetailView metaBar — 메모 본문 노출

**파일**: `Camork/Camork/Gallery/PhotoDetailView.swift`

- `HStack` → `VStack(alignment: .leading)` — 날짜/장소/메모를 세로로 쌓음
- 메모 본문 `lineLimit(2)` 로 truncated 표시 (이전엔 `note.text` 아이콘만)
- 우측 `note.text` 아이콘 제거 (본문이 직접 보이므로 중복)

## 4. PhotoDetailView 좌우 스와이프 페이지네이션

**파일**: `Camork/Camork/Gallery/PhotoDetailView.swift`, `Camork/Camork/Camera/CameraScreen.swift`, `Camork/Camork/Gallery/SessionDetailScreen.swift`

### Signature 변경
```swift
// Before
init(photo: Photo, data: Data, memoEditor: ..., onDismiss: ..., session: ..., sharePreparer: ...)

// After
init(
    photos: [Photo],
    initialPhotoId: UUID,
    initialData: Data,
    dataLoader: @escaping (Photo) async throws -> Data,
    memoEditor: ...,
    onDismiss: ...,
    session: ...,
    sharePreparer: ...
)
```

### 페이저 구조
- `TabView(selection: $currentIndex).tabViewStyle(.page(indexDisplayMode: .never))`
- `imageDataCache: [UUID: Data]`, `decodedImageCache: [UUID: UIImage]` — lazy load
- 인접(±1) 사진 **prefetch** — 페이지 전환 시 끊김 최소화
- `savedNotes: [UUID: String?]` — 사진별 메모 분리

### 호출부
- **CameraScreen**: `photos: [item.photo]` 단일 모드
- **SessionDetailScreen**: `photos: photos` 전체 배열 → 좌우 스와이프 활성

## 5. PhotoDetailView 아래 스와이프 dismiss

**파일**: `Camork/Camork/Gallery/PhotoDetailView.swift`

- `DragGesture(minimumDistance: 20)` 를 `simultaneousGesture` 로 추가
- vertical-dominant downward drag만 reaction (`abs(height) > abs(width)`)
- 드래그 중 `VStack.offset(y: dismissOffset)` 으로 끌려 내려가는 효과
- 임계치 120pt 넘으면 `onDismiss()`, 안 넘으면 spring으로 원위치
- **zoom > 1.0 자동 비활성** — UIScrollView pan이 vertical drag를 가로채 outer gesture 비활성

## 6. AppIcon 리디자인 적용

**파일**: `Camork/Resources/Assets.xcassets/AppIcon.appiconset/{AppIcon-Default,AppIcon-Dark,AppIcon-Tinted}.png`

- 받은 6 variant 중 3개 슬롯 매핑:
  - `iOS-Default` → `AppIcon-Default.png`
  - `iOS-Dark` → `AppIcon-Dark.png`
  - `iOS-TintedLight` → `AppIcon-Tinted.png`
- Clear 2종은 Asset Catalog 슬롯 없음 → 시스템 자동 생성에 위임
- **Default 알파 채널 제거** (App Store marketing icon 요구사항) — Core Graphics Swift script로 흰 배경 합성 후 PNG 재인코딩

## 7. 빌드 번호

**파일**: `project.yml`

- `CURRENT_PROJECT_VERSION: 12` → `13` → `14` → `15` (각 단계마다 App Store Connect 거부로 인한 증가)
- 매 변경마다 `xcodegen generate` 실행

## 영향 받은 파일 요약

| 파일 | 변경 |
|---|---|
| `GalleryScreen.swift` | List → ScrollView, bottom fade overlay |
| `RootTabView.swift` | bottomChromeFade / preference key 제거 |
| `SessionDetailScreen.swift` | Bottom fade overlay, PhotoDetailView 호출부 |
| `PhotoDetailView.swift` | 페이저화, dismiss gesture, 메모 본문 노출 |
| `CameraScreen.swift` | PhotoDetailView 호출부 |
| `project.yml` | 빌드 번호 증가 |
| `Assets.xcassets/AppIcon.appiconset/` | 아이콘 3종 교체, Default 알파 제거 |

테스트는 영향 없음 (`PhotoDetailView` 직접 테스트 없음). 컴파일 에러 없음 확인됨.
