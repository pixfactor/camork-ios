# Plan A 완료 보고서

- **완료일:** 2026-05-19
- **브랜치:** `rebuild/v2`
- **산출:** 빌드되는 빈 SwiftUI 앱 + DesignSystem 토큰 + 기본 컴포넌트 + 한/영 String Catalog + 백그라운드 가림막 hook

## 검증 결과

### 자동 (xcodebuild)
- ✅ `xcodebuild build` SUCCEEDED (iPhone 17 Pro 시뮬레이터, `$CAMORK_SIM`, `CODE_SIGNING_ALLOWED=NO`)
- ✅ `xcodebuild clean` + `xcodebuild test` 전체 회귀 **7건 모두 통과** (9.6초)
  - ThemeTests: Spacing 8pt 그리드, CornerRadius 오름차순
  - ColorsTests: AccentColor RGBA(라이트 ≠ 다크), 시멘틱 컬러 인스턴스화
  - CamorkButtonStyleTests: primary→accent / secondary→systemDefault / destructive→destructive
- ✅ `xcodegen generate` 안정 동작 — `Camork/Info.plist` 자동 생성 (.gitignore로 제외), `Camork.xcodeproj` 갱신
- ✅ Assets.car에 AccentColor 라이트(Any default) + 다크 variant 정상 컴파일

### 수동 시각 검증 (사용자 책임 — Xcode ⌘R)
다음 항목을 시뮬레이터에서 직접 확인하세요:
- [ ] 다크 시스템 모드에서 다크 톤으로 뜸
- [ ] 라이트 시스템 모드로 전환(시뮬레이터 ⇧⌘A)하면 라이트 톤으로 자연스럽게 변환
- [ ] 3개 탭(카메라/현장/설정) SF Symbol과 함께 정상 표시
- [ ] 탭 전환 매끄럽게
- [ ] 시뮬레이터 언어 영어로 변경 시 탭 라벨 "Camera / Sites / Settings"
- [ ] 한국어 + Dynamic Type AX5에서 탭 라벨 잘림 없음
- [ ] Xcode `CamorkButton.swift` Preview의 Dark/Light/AX5 3가지 모두 정상 렌더링, primary와 secondary 시각 위계 구분
- [ ] Xcode `CamorkCard.swift` Preview의 Dark/Light/AX5 모두 정상

## Commit 이력 (Lore Commit Protocol)

```
29f0664 backport Task 6 errata to Plan A v3 source — Bundle lookup and AccentColor appearances
7ded077 add Korean-first String Catalog with twelve initial keys for tabs, placeholders and buttons
48ccdd0 add CamorkCard container with continuous corners and elevated surface
5318745 add CamorkButton with HIG-compliant role styling and TintToken-based test surface
c950b2b add semantic color mapping and AccentColor with corrected trait verification
dd75400 add Spacing and CornerRadius design tokens with parity tests
89ed504 add iPhone-only SwiftUI app shell with placeholder tabs and background-shield hook
3ac7eac realign Plan A v3 environment assumptions to Xcode 26 / iPhone 17 / Swift 5 mode
bc33664 fix Plan A v3 ColorsTests bundle lookup and harden appearance comparison
4491b90 revise Plan A to v3 with Lore-aligned commits and TintToken-based test stability
```

## Plan A 실행 중 발견된 추가 errata 2건 (이미 plan source에 backport)

1. **Bundle lookup**: `Bundle.main`은 unit test에서 host app bundle이 아닐 수 있어 fragile → app target에 `internal final class CamorkBundleToken {}` 두고 `Bundle(for: CamorkBundleToken.self)` 사용. **Plan B+의 모든 Asset 자산 lookup에 답습.**
2. **AccentColor JSON `appearances` 패턴**: light/dark 둘 다 명시 시 trait Any fallback 부재로 lookup nil → light는 `appearances` 키 없이 Any default + dark만 variant. **iOS 표준. Plan B+ 모든 Asset Catalog 자산에 답습.**

(상세는 `implementation-notes.html` 또는 plan A v3 부록 §A 참조)

## Plan B 진입 전 결정/확인 필요 (9개 인계)

1. **entitlements** — `AVFoundation` 자체는 entitlement 불필요하지만, Background mode (카메라 백그라운드 캡처) 사용 여부 결정.
2. **메타데이터 영속 방식** — SQLite (GRDB) vs JSON 파일. Spec §15. Plan B 시작 전 결정 필요. 트리거: 사진 수 1만 이상 시 검색/필터 성능.
3. **동시성 ADR (Plan B 첫 task)** — `actor MediaStorage`/`actor SessionManager`의 reentrancy 정책, `@MainActor` UI ↔ actor 도메인 경계, 테스트 격리 방식, AVFoundation 백그라운드 큐 ↔ actor 충돌.
4. **HEIC vs JPEG** — Spec §6.5에서 HEIC 기본 채택. 변경 시 Plan B에서 반영.
5. **CoreLocation 권한 요청 시점** — Spec §15. 앱 첫 실행 vs 첫 촬영 vs 설정에서 명시적. 첫 촬영 직전이 마찰 최소.
6. **실기기 빌드 시 사이닝 재정렬** — 현재 `CODE_SIGN_STYLE: Automatic` + `CODE_SIGNING_ALLOWED=NO` 조합은 시뮬레이터 전용. 실기기/TestFlight/App Store 배포 시 `DEVELOPMENT_TEAM` 설정 + 사이닝 옵션 재정렬 필요.
7. **AVFoundation TDD 한계 정책** — `AVCaptureSession`은 시뮬레이터에서 캡처 제한. configuration 빌더는 단위 테스트하고, 실제 캡처는 실기기 시각 검증으로 분기. Plan B 정책 §0에 보강.
8. **actor reentrancy / 의존성 주입 ADR** — Plan B 첫 task로 ADR 작성. Swift Testing의 `await` 검증 패턴이 actor 모델과 호환되는지.
9. **placeholder 영어 카피 출시 전 교체** — `placeholder_*_description`의 "Coming soon" / "준비 중"은 v1 Core 중립 카피. 출시 전 Plan E에서 최종 카피 또는 description 제거.

## 미해결 (출시 전 결정)

- **AccentColor 정확한 hex** — 현재 라이트 `#FF9500` / 다크 `#FF9F00` 임시. frontend-design 단계 또는 디자이너 입력 / 사용자 확정 필요. Plan E 전.
- **App Icon 1024×1024 이미지** — Plan E 추가.
- **백그라운드 가림막 실구현** — Plan E에서 `AppBackgroundShield` 실제 ScenePhase + 오버레이 + 카메라 세션 정지 hook 구현.
- **Swift 6 전환 시점** — Plan B 동시성 ADR 작성 후 별도 결정. strict concurrency 영향 검토.

## 다음 단계

**Plan B (Storage + Sessions + Camera) 작성으로 진입.** 위 9개 인계 항목을 brainstorming/시작 시 정렬.

특히 **Plan B 첫 task로 "동시성 ADR" 작성** — 이게 정해져야 actor 모델 + AVFoundation + Swift Testing이 흔들리지 않음.
