# Camork v1 Core — Plan A: 프로젝트 셋업 + DesignSystem (v3)

> **개정 이력**:
> - v2 (2026-05-19): momus 리뷰 (Critical 9 + Should-fix 7) 반영
> - v3 (2026-05-19): 추가 critic 8개 항목 반영 + Lore Commit Protocol 정렬 (C1) + TintToken 도입 (C2) + xcodebuild test 통일 (C3) + tracked Info.plist 처리 (C4) + 인계 항목 9개 표기 (C5) + Task 3 단계 정리 (S1) + placeholder 카피 중립화 (S2) + 환경변수 destination (S3) + UIColor bundle 명시 (S4) + commit 예시 전부 Lore 형식 교체
>
> 부록 §A에 두 차례 리뷰 ↔ 반영 위치 매핑.

## Commit Policy

**실행 시점의 가장 가까운 `AGENTS.md`, `CLAUDE.md`, 또는 사용자 지시가 본 plan의 commit 예시보다 우선한다.** 아래 commit 메시지는 **Codex 환경의 Lore Commit Protocol** 기준 예시이며, 다른 환경(예: 표준 Conventional Commits, Git Karma)에서 실행할 경우 해당 환경의 규칙에 맞게 메시지·포맷을 조정한다. Lore 형식 골격:

```
<intent line — 왜 이 변경을 했는지>

<맥락, 제약, 접근 이유>

Constraint: <지키려는 제약>
Rejected: <고려했지만 채택 안 한 대안 + 이유>
Confidence: high|medium|low
Scope-risk: narrow|moderate|broad
Directive: <다음 작업으로의 인계 / 행동 지침>
Tested: <실제 검증한 것>
Not-tested: <검증하지 못한 것 + 어디서 보완할지>
```

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** XcodeGen 기반의 빈 SwiftUI 앱이 빌드·실행되고, 다크모드 1차(시스템 따름) + 시멘틱 컬러 + 기본 카드/버튼 컴포넌트가 갖춰진 상태.

**Architecture:** `project.yml` 단일 진실 소스 → `xcodegen generate`로 `Camork.xcodeproj` 재생성. SwiftUI App entry는 `CamorkApp.swift`. Root `TabView` 3개 placeholder. `DesignSystem/Theme.swift`에 토큰, `Colors.swift`에 semantic color 매핑. `DesignSystem/Components/`에 `CamorkCard`, `CamorkButton`. Localizable은 String Catalog(`.xcstrings`)에 JSON 직접 작성 (GUI 의존 X). Swift Testing(`@Test`)으로 토큰·UIColor 단위 검증.

**Tech Stack:** Swift 5.9, SwiftUI, XcodeGen, Swift Testing, iOS 17+, Xcode 16, String Catalog (`.xcstrings`).

**선행 조건:**
- XcodeGen 설치 (`brew install xcodegen`)
- **Xcode 16 + iOS 17 Simulator + iPhone 16 Pro 시뮬레이터** (Task 0에서 검증 → 없으면 가용 기기로 fallback)
- 부모 `/Users/jedel/Projects/CLAUDE.md`, `.claude/references/apple-hig.md`, 앱 `CLAUDE.md` 사전 일독

**완료 기준:**
- 시뮬레이터에서 빌드 + 실행 → 다크 1차 + 라이트 모드 자동 대응 + 3개 탭 + 한/영 전환
- `xcodebuild test` 패스 (의미 있는 단위 테스트 — toy 아님). 본 프로젝트는 XcodeGen/Xcode 기반이므로 `swift test`는 사용하지 않음.
- Plan B 진입 가능 상태 + Task 12 보고서에 Plan B 인계 메모

---

## SwiftUI 테스트 정책 (Plan A에서 굳혀 Plan B~E에 일관 적용)

(momus S2 반영)

1. **단위 테스트의 책임은 "로직 검증"이지 "SwiftUI 렌더 검증"이 아니다.**
2. View body 자체의 시각 검증은 **Xcode Preview** (라이트/다크/AX5)에 위임.
3. 분기/계산이 있는 코드(예: `tintColor` 분기, 자동 텍스트 생성)는 **internal 또는 `static func`로 추출하고 단위 테스트로 검증**.
4. View 자체에는 "타입 컴파일 가드" 정도의 toy 테스트는 두지 않는다. 의미 없는 회귀 방지보다는 Preview 시각 검증이 낫다.
5. `UIColor(named:in:compatibleWith:)` 처럼 **에셋 카탈로그 값을 trait별로 검증할 수 있는 경우**는 단위 테스트로 검증.

---

## File Structure

```
Camork/
├─ CamorkApp.swift                — @main, App entry
├─ RootTabView.swift              — Root TabView (3개 placeholder)
├─ Resources/
│  ├─ Assets.xcassets/
│  │  ├─ AccentColor.colorset/Contents.json   — 라이트/다크 명시
│  │  └─ AppIcon.appiconset/Contents.json     — 1024 슬롯 (이미지는 Plan E)
│  └─ Localizable.xcstrings       — 한/영 (JSON 직접 작성)
├─ DesignSystem/
│  ├─ Theme.swift                 — Spacing, CornerRadius 토큰
│  ├─ Colors.swift                — Semantic color 매핑
│  └─ Components/
│     ├─ CamorkCard.swift         — 카드 컨테이너
│     └─ CamorkButton.swift       — 통일 버튼 (3 role, HIG 준수 스타일 분기)
├─ Views/
│  ├─ CameraPlaceholderView.swift
│  ├─ GalleryPlaceholderView.swift
│  └─ SettingsPlaceholderView.swift
└─ AppShell/
   └─ AppBackgroundShield.swift   — 백그라운드 가림막 (Plan A에 placeholder hook, Plan E에서 구현)

CamorkTests/
├─ ThemeTests.swift               — Spacing/CornerRadius 토큰 검증
├─ ColorsTests.swift              — AccentColor 라이트/다크 다른 값 검증 (UIColor trait)
└─ CamorkButtonStyleTests.swift   — tintColor / buttonStyle role 분기 검증

project.yml                       — XcodeGen 단일 진실 소스
.gitignore                        — Plan 진입 전 sanity check
```

(momus S4 반영: `AppShell/AppBackgroundShield.swift` placeholder hook을 Plan A에서 둠 → Plan E에서 구현. Plan A에서는 빈 modifier로 두고 Root에 attach.)

---

## Phase 0 — 사전 점검 (시뮬레이터 / .gitignore)

### Task 0: 환경 점검

- [ ] **Step 1: XcodeGen 설치 확인**

```bash
which xcodegen && xcodegen --version
```
Expected: `xcodegen 2.x.x` 출력. 없으면 `brew install xcodegen`.

- [ ] **Step 2: 시뮬레이터 가용성 확인** (momus C8)

```bash
xcrun simctl list devices available | grep -E "iPhone (16|15) Pro"
```
Expected: `iPhone 16 Pro` 또는 `iPhone 15 Pro` 한 줄 이상. 둘 다 없으면 Xcode → Settings → Platforms에서 iOS 17 시뮬레이터 다운로드.

**이 plan은 destination을 환경변수 `CAMORK_SIM`으로 통일.** Plan 본문은 `iPhone 16 Pro` 가정으로 작성. 다른 기기로 진행할 때는 plan 문서를 수정하지 말고 셸에서:

```bash
export CAMORK_SIM="iPhone 16 Pro"   # 또는 "iPhone 15 Pro" 등 가용 기기
```

이 plan의 모든 xcodebuild 명령은 `name=$CAMORK_SIM` 로 일관 적용. **plan 문서 자체를 sed로 치환하지 말 것** — git 히스토리에 환경 차이가 흔적으로 남음. 환경변수가 없을 때만 fallback으로 `iPhone 16 Pro` 사용.

- [ ] **Step 3: 현재 `.gitignore` 검증 + 보강 + tracked Info.plist 처리** (momus S1 + v3 C4)

```bash
cat .gitignore | grep -E "(xcodeproj|DerivedData|build/|Info\.plist)"
```
Expected:
- `DerivedData/`, `build/` 보임
- `Camork.xcodeproj/` 는 **주석 처리** (XcodeGen 산출물이지만 일단 commit — 추후 정책 변경 가능)
- **`Camork/Info.plist`** 라인 보임

`Camork/Info.plist` 라인이 없으면 `.gitignore` 끝에 다음 추가:

```
# XcodeGen 자동 생성 plist
Camork/Info.plist
```

**그리고 즉시 tracked 상태 확인** — `.gitignore`는 이미 tracked인 파일에는 효과 없음:

```bash
git ls-files Camork/Info.plist
```

- 결과가 빈 줄: tracked 아님 (OK)
- 결과가 `Camork/Info.plist` 출력: 이미 tracked 상태 → 다음 절차로 untrack:

```bash
git rm --cached Camork/Info.plist 2>/dev/null || true
```

`.gitignore` 변경 + (필요 시) `git rm --cached`까지 한 commit에 묶어 단독 commit. commit 메시지는 Lore 형식 (위 Commit Policy 참조).

---

## Phase 1 — XcodeGen 셋업

### Task 1: project.yml 작성

**Files:**
- Create: `project.yml`

- [ ] **Step 1: 작성** (momus C1, C2, C3, C9 반영)

```yaml
name: Camork
options:
  bundleIdPrefix: com.camork
  deploymentTarget:
    iOS: "17.0"
  xcodeVersion: "16.0"
  createIntermediateGroups: true

settings:
  base:
    SWIFT_VERSION: "5.9"
    TARGETED_DEVICE_FAMILY: "1"   # iPhone only
    ENABLE_USER_SCRIPT_SANDBOXING: YES

targets:
  Camork:
    type: application
    platform: iOS
    sources:
      - path: Camork
        excludes:
          - "**/.DS_Store"
          - "Info.plist"          # XcodeGen이 info.properties로 자동 생성, 중복 방지
    info:
      path: Camork/Info.plist
      properties:
        UILaunchScreen: {}
        NSCameraUsageDescription: "현장 기록을 위해 카메라 사용 권한이 필요합니다."
        NSLocationWhenInUseUsageDescription: "촬영 위치를 사진에 함께 기록하기 위해 위치 권한을 요청합니다."
        NSFaceIDUsageDescription: "앱 잠금을 해제하기 위해 Face ID를 사용합니다."
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
        # UIUserInterfaceStyle: 의도적으로 미설정 — 시스템 따라감 + Asset Catalog의 다크 우선 컬러로 1차 효과 (momus S5)
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.camork.app
        MARKETING_VERSION: "1.0.0"
        CURRENT_PROJECT_VERSION: "1"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        SWIFT_EMIT_LOC_STRINGS: "YES"
        ENABLE_PREVIEWS: "YES"
        CODE_SIGN_STYLE: Automatic
        # DEVELOPMENT_TEAM 의도적 미설정 — 개인/회사 Mac 차이 흡수.
        # 시뮬레이터 빌드는 CODE_SIGNING_ALLOWED=NO 명령행 옵션으로 회피 (모든 xcodebuild 명령에 적용).
    entitlements:
      path: Camork/Camork.entitlements

  CamorkTests:
    type: bundle.unit-test
    platform: iOS
    sources: CamorkTests
    dependencies:
      - target: Camork
    # BUNDLE_LOADER/TEST_HOST는 XcodeGen이 자동 설정 (momus C3)
```

**주요 변경 (v1 대비):**
- `INFOPLIST_KEY_UILaunchScreen_Generation: true` 라인 제거 (momus C2)
- `BUNDLE_LOADER`/`TEST_HOST` 수동 라인 제거, XcodeGen 자동 위임 (momus C3)
- `UIUserInterfaceStyle: Dark` 제거 — 시스템 따라감 + 다크 1차는 Asset Catalog 컬러로 표현 (momus S5)
- `sources.excludes`에 `Info.plist` 추가 — XcodeGen 자동 생성 plist와 충돌 방지 (momus C1)
- `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor` 추가 — `.tint` 미지정 시에도 자동 적용

- [ ] **Step 2: 생성 검증**

```bash
xcodegen generate --spec project.yml
```
Expected: `Loaded project ... Generated project successfully` 출력. `Camork.xcodeproj/`와 `Camork/Info.plist`(자동 생성됨)가 보임.

- [ ] **Step 3: Info.plist 자동 생성 확인**

```bash
ls -la Camork/Info.plist && head -5 Camork/Info.plist
```
Expected: 파일 존재 + 첫 줄 `<?xml version="1.0" encoding="UTF-8"?>`.

### Task 2: 디렉토리 + entitlements + Assets 골격

**Files:**
- Create: `Camork/Camork.entitlements`
- Create: `Camork/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`
- Create: `Camork/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `Camork/Resources/Assets.xcassets/Contents.json`
- Create: 디렉토리들 (`DesignSystem/Components`, `Views`, `AppShell`)

- [ ] **Step 1: 디렉토리 생성**

```bash
mkdir -p Camork/DesignSystem/Components
mkdir -p Camork/Views
mkdir -p Camork/AppShell
mkdir -p Camork/Resources/Assets.xcassets/AccentColor.colorset
mkdir -p Camork/Resources/Assets.xcassets/AppIcon.appiconset
mkdir -p CamorkTests
```

- [ ] **Step 2: 빈 entitlements** (momus S4: Plan B 진입 시 검토할 placeholder)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```
파일: `Camork/Camork.entitlements`.

(v1 Core에서 entitlement는 없음. Plan B에서 AVFoundation 사용 시 마이크/Background mode 같은 entitlement가 필요할지 검토 — Task 12 보고서에 인계 메모.)

- [ ] **Step 3: AccentColor JSON** (momus C5 — 라이트/다크 명시)

`Camork/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`:
```json
{
  "colors" : [
    {
      "appearances" : [
        { "appearance" : "luminosity", "value" : "light" }
      ],
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.000",
          "green" : "0.584",
          "red" : "1.000"
        }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [
        { "appearance" : "luminosity", "value" : "dark" }
      ],
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.000",
          "green" : "0.624",
          "red" : "1.000"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

(라이트: rgb(255, 149, 0) = `#FF9500`, 다크: rgb(255, 159, 0) = `#FF9F00`. 정확한 값은 frontend-design 단계에서 디자이너 확정 — Task 12 보고서에 미해결로 기록.)

- [ ] **Step 4: AppIcon JSON** (이미지는 Plan E)

`Camork/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`:
```json
{
  "images" : [
    {
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 5: Assets root Contents**

`Camork/Resources/Assets.xcassets/Contents.json`:
```json
{ "info" : { "author" : "xcode", "version" : 1 } }
```

---

## Phase 2 — App Entry + Root TabView

### Task 3: 빈 백그라운드 가림막 placeholder (momus S4)

**Files:**
- Create: `Camork/AppShell/AppBackgroundShield.swift`

- [ ] **Step 1: 작성**

```swift
import SwiftUI

/// 백그라운드 진입 시 컨텐츠를 가리는 modifier.
/// v1 Core 에서는 placeholder. Plan E에서 실제 가림막 + 카메라 세션 정지 hook 구현.
struct AppBackgroundShieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
        // Plan E: ScenePhase 감지 + 오버레이 추가
    }
}

extension View {
    /// 앱이 백그라운드 진입 시 보호 가림막을 씌운다 (Plan E에서 활성화).
    func appBackgroundShield() -> some View {
        modifier(AppBackgroundShieldModifier())
    }
}
```

- [ ] **Step 2: 파일만 생성 후 다음 task로** (v3 S1 — Task 3에서는 빌드 실패가 예정되어 있어 실행자 혼란을 유발 → 빌드 검증은 Task 4에서 통합 수행)

이 task에서는 파일 생성만으로 충분. 다른 source 파일이 없으니 단독 빌드 시도하지 말 것. Task 4에서 `CamorkApp`/`RootTabView` 추가 후 통합 빌드.

### Task 4: CamorkApp + RootTabView (한 묶음 commit)

**Files:**
- Create: `Camork/CamorkApp.swift`
- Create: `Camork/RootTabView.swift`
- Create: `Camork/Views/CameraPlaceholderView.swift`
- Create: `Camork/Views/GalleryPlaceholderView.swift`
- Create: `Camork/Views/SettingsPlaceholderView.swift`

- [ ] **Step 1: 각 placeholder 작성** (LocalizedStringKey 직접 사용 — momus C7)

`CameraPlaceholderView.swift`:
```swift
import SwiftUI

struct CameraPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "placeholder_camera_title",
            systemImage: "camera",
            description: Text("placeholder_camera_description")
        )
    }
}
```

`GalleryPlaceholderView.swift`:
```swift
import SwiftUI

struct GalleryPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "placeholder_gallery_title",
            systemImage: "square.grid.2x2",
            description: Text("placeholder_gallery_description")
        )
    }
}
```

`SettingsPlaceholderView.swift`:
```swift
import SwiftUI

struct SettingsPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "placeholder_settings_title",
            systemImage: "gearshape",
            description: Text("placeholder_settings_description")
        )
    }
}
```

`ContentUnavailableView`는 LocalizedStringKey를 직접 받음 → String Catalog 자동 lookup.

- [ ] **Step 2: RootTabView** (LocalizedStringKey 통일)

```swift
import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            CameraPlaceholderView()
                .tabItem { Label("camera_tab_label", systemImage: "camera") }

            GalleryPlaceholderView()
                .tabItem { Label("gallery_tab_label", systemImage: "square.grid.2x2") }

            SettingsPlaceholderView()
                .tabItem { Label("settings_tab_label", systemImage: "gearshape") }
        }
        .appBackgroundShield()
    }
}

#Preview("Dark") {
    RootTabView().preferredColorScheme(.dark)
}

#Preview("Light") {
    RootTabView().preferredColorScheme(.light)
}

#Preview("AX5") {
    RootTabView()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
```

(momus S3: AX5 Preview 추가, S7: 한국어 라벨이 AX5에서 잘리지 않는지 확인)

- [ ] **Step 3: CamorkApp.swift**

```swift
import SwiftUI

@main
struct CamorkApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
```

- [ ] **Step 4: xcodegen 재생성 + 빌드** (Localizable이 없어도 SwiftUI는 key를 그대로 표시함, 다음 task에서 채움)

```bash
xcodegen generate && \
xcodebuild -scheme Camork \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  build 2>&1 | tail -20
```
Expected: `BUILD SUCCEEDED`. Localizable 키가 raw로 표시될 수 있음 (정상 — Task 7에서 String Catalog 추가).

- [ ] **Step 5: 커밋** (Lore 형식 예시)

```bash
git add project.yml Camork/
git commit -F- <<'EOF'
add iPhone-only SwiftUI app shell with placeholder tabs and background-shield hook

세션의 첫 빌드 가능 상태를 만든다. project.yml은 XcodeGen 단일 진실 소스로 두고
RootTabView 3개 탭(카메라/현장/설정)에 placeholder를 띄워 다음 plan으로의 인계
지점을 명확히 한다. UIUserInterfaceStyle은 강제하지 않고 시스템 appearance를 따라
다크 1차이되 라이트 자동 대응을 보장한다.

Constraint: iPhone only, iOS 17+, 다크 1차이지만 라이트 자동 대응 검증 필수, Asset Catalog의 다크 우선 컬러로 1차 효과 표현
Rejected: UIUserInterfaceStyle: Dark 강제 — 라이트 검증 의도와 충돌하며 시스템 따라감 정책 위배
Confidence: high
Scope-risk: narrow
Directive: 후속 task에서 DesignSystem 토큰 + 컴포넌트 + String Catalog 작업이 이어진다
Tested: xcodebuild build 성공 + 시뮬레이터 3 탭 보임 + 다크/라이트 자동 대응
Not-tested: 실기기 빌드(서명), 한국어/영어 전환(다음 task의 String Catalog 추가 후)
EOF
```

---

## Phase 3 — DesignSystem 토큰

### Task 5: Theme.swift (간격/모서리)

**Files:**
- Create: `Camork/DesignSystem/Theme.swift`
- Test: `CamorkTests/ThemeTests.swift`

- [ ] **Step 1: 실패 테스트 작성**

```swift
// CamorkTests/ThemeTests.swift
import Testing
@testable import Camork

@Suite("Theme tokens")
struct ThemeTests {
    @Test("Spacing은 8pt 그리드를 따른다")
    func spacingFollows8ptGrid() {
        #expect(Spacing.xs == 4)
        #expect(Spacing.sm == 8)
        #expect(Spacing.md == 16)
        #expect(Spacing.lg == 24)
        #expect(Spacing.xl == 32)
        // 모든 값이 4의 배수
        for value in [Spacing.xs, Spacing.sm, Spacing.md, Spacing.lg, Spacing.xl] {
            #expect(value.truncatingRemainder(dividingBy: 4) == 0)
        }
    }

    @Test("CornerRadius 5단계")
    func cornerRadiusStandards() {
        #expect(CornerRadius.sm == 6)
        #expect(CornerRadius.md == 12)
        #expect(CornerRadius.lg == 16)
        #expect(CornerRadius.xl == 24)
        // 오름차순
        let values = [CornerRadius.sm, CornerRadius.md, CornerRadius.lg, CornerRadius.xl]
        #expect(values == values.sorted())
    }
}
```

- [ ] **Step 2: 실패 확인 (host app 부팅 포함)** (momus C4 — 실제 시뮬레이터에서 부팅되는지)

```bash
xcodebuild -scheme Camork \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  test 2>&1 | tail -15
```
Expected: 컴파일 단계에서 `Spacing` not found. 즉, **컴파일 실패**. 만약 컴파일은 되고 시뮬레이터가 부팅 안 되면 host app 연결 문제 — `bundle.unit-test` dependency 재확인 필요.

- [ ] **Step 3: 최소 구현**

```swift
// Camork/DesignSystem/Theme.swift
import SwiftUI

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum CornerRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}
```

- [ ] **Step 4: 테스트 통과 + host app 부팅 확인**

```bash
xcodegen generate && \
xcodebuild -scheme Camork \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  test 2>&1 | tail -15
```
Expected: `Test Suite 'ThemeTests' passed`. 시뮬레이터 부팅 로그가 보이면 host app 연결 정상.

- [ ] **Step 5: 커밋**

```bash
git add Camork/DesignSystem/Theme.swift CamorkTests/ThemeTests.swift
git commit -F- <<'EOF'
add Spacing and CornerRadius design tokens with parity tests

후속 컴포넌트들이 일관된 spacing/radius를 사용하도록 8pt 그리드(4·8·16·24·32)와
5단계 모서리(6·12·16·24)를 도입한다. enum 정적 상수로 두어 import 없이 사용 가능하며
단위 테스트로 값의 회귀(특히 4의 배수, 오름차순)를 막는다.

Constraint: 8pt 그리드 준수, 모든 Spacing 값은 4의 배수, CornerRadius 오름차순
Rejected: 자유로운 CGFloat 값 — 일관성 흔들림 + 디자인 시스템 도입 의의 무력화
Confidence: high
Scope-risk: narrow
Directive: 추가 토큰(Shadow, Motion) 필요 시 같은 enum 패턴 확장
Tested: ThemeTests 모두 통과 — 8pt 그리드, 오름차순
Not-tested: 실 사용 시 시각적 만족도 — Preview 시각 검증 단계에서
EOF
```

### Task 6: Colors.swift — Semantic + AccentColor trait 검증

**Files:**
- Create: `Camork/DesignSystem/Colors.swift`
- Test: `CamorkTests/ColorsTests.swift`

- [ ] **Step 1: 실패 테스트** (momus C5 — 실질적 검증)

```swift
// CamorkTests/ColorsTests.swift
import Testing
import SwiftUI
import UIKit
@testable import Camork

@Suite("Semantic colors")
struct ColorsTests {
    @Test("AccentColor는 라이트/다크에서 다른 RGB를 가진다")
    func accentDiffersBetweenAppearances() {
        // Asset Catalog의 AccentColor를 명시 bundle로 lookup + trait 분해 비교 (v3 S4)
        // bundle을 명시하지 않으면 테스트 호스트 환경에 따라 lookup 실패 가능.
        let bundle = Bundle(for: BundleToken.self)
        let light = UIColor(named: "AccentColor", in: bundle, compatibleWith:
            UITraitCollection(userInterfaceStyle: .light))
        let dark = UIColor(named: "AccentColor", in: bundle, compatibleWith:
            UITraitCollection(userInterfaceStyle: .dark))
        #expect(light != nil, "AccentColor가 앱 번들에 등록돼 있어야 함")
        #expect(dark != nil)
        #expect(light != dark, "라이트/다크 변형이 동일하면 다크모드 전환이 무의미")
    }

    /// 번들 lookup의 명시 키. test target 안의 어떤 클래스든 OK — Bundle(for:)이 그 클래스가 속한 번들을 반환.
    private final class BundleToken {}

    @Test("Camork 시멘틱 컬러는 인스턴스화 가능")
    func semanticColorsInstantiate() {
        // 시스템 컬러로 위임됐는지 확인 — 시스템 컬러는 옵셔널이 아니므로 인스턴스화만 검증
        _ = Color.camorkBackground
        _ = Color.camorkSecondaryBackground
        _ = Color.camorkTertiaryBackground
        _ = Color.camorkSeparator
        _ = Color.camorkFill
        _ = Color.camorkAccent
    }
}
```

- [ ] **Step 2: 실패 확인 → 최소 구현**

```swift
// Camork/DesignSystem/Colors.swift
import SwiftUI

extension Color {
    /// 앱 강조색 — Asset Catalog의 AccentColor를 자동 사용.
    static let camorkAccent = Color.accentColor

    /// 1차 배경 (다크모드에서 검정 계열)
    static let camorkBackground = Color(.systemBackground)

    /// 2차 배경 — 카드/그룹
    static let camorkSecondaryBackground = Color(.secondarySystemBackground)

    /// 3차 배경
    static let camorkTertiaryBackground = Color(.tertiarySystemBackground)

    /// 구분선
    static let camorkSeparator = Color(.separator)

    /// 칩/빈 영역 등 subtle fill
    static let camorkFill = Color(.systemFill)
}
```

- [ ] **Step 3: 테스트 통과**

```bash
xcodegen generate && \
xcodebuild -scheme Camork \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  test 2>&1 | tail -15
```
Expected: `Test Suite 'ColorsTests' passed`.

- [ ] **Step 4: 커밋**

```bash
git add Camork/DesignSystem/Colors.swift CamorkTests/ColorsTests.swift
git commit -F- <<'EOF'
add semantic color mapping and AccentColor with appearance-aware verification

다크모드 자동 대응을 코드 차원에 강제한다. SwiftUI Color extension은 모두 시스템
semantic 컬러(systemBackground 등)로 위임하고, AccentColor는 Asset Catalog에서
라이트/다크 두 슬롯을 명시한다. UIColor.resolvedColor(with:)로 trait별 RGB가
실제로 다른지 검증해 단일 슬롯 회귀를 막는다.

Constraint: 모든 컬러는 semantic 매핑 또는 Asset Catalog 변형 정의, hex 하드코딩 금지
Rejected: Color(red:green:blue:) 하드코딩 — 다크모드 자동 대응 불가
Confidence: high
Scope-risk: narrow
Directive: 추가 BrandColor가 필요하면 Asset Catalog에 라이트/다크 변형 등록 + Color extension에 노출
Tested: ColorsTests — light != dark 검증, 시멘틱 컬러 인스턴스화 가능
Not-tested: 정확한 hex 값 — frontend-design 단계에서 디자이너 확정
EOF
```

---

## Phase 4 — 기본 컴포넌트 (로직 분리해서 테스트)

### Task 7: CamorkButton (역할별 스타일 — HIG 준수)

**Files:**
- Create: `Camork/DesignSystem/Components/CamorkButton.swift`
- Test: `CamorkTests/CamorkButtonStyleTests.swift`

(momus S6: `borderedProminent`는 primary와 destructive만, secondary는 `.bordered` — HIG §10 "borderedProminent 1개 원칙")

- [ ] **Step 1: 실패 테스트** (v3 C2 — `TintToken` enum으로 비교 안정화)

`Color`의 `==`는 내부 representation에 의존해 불안정 → 토큰 enum으로 비교한다.

```swift
// CamorkTests/CamorkButtonStyleTests.swift
import Testing
@testable import Camork

@Suite("CamorkButton style resolution")
struct CamorkButtonStyleTests {
    @Test("primary는 borderedProminent + accent token")
    func primary() {
        let resolved = CamorkButton.resolveStyle(.primary)
        #expect(resolved.isProminent == true)
        #expect(resolved.tint == .accent)
    }

    @Test("secondary는 bordered + systemDefault (HIG: borderedProminent 1개 원칙)")
    func secondary() {
        let resolved = CamorkButton.resolveStyle(.secondary)
        #expect(resolved.isProminent == false)
        #expect(resolved.tint == .systemDefault)
    }

    @Test("destructive는 borderedProminent + destructive token")
    func destructive() {
        let resolved = CamorkButton.resolveStyle(.destructive)
        #expect(resolved.isProminent == true)
        #expect(resolved.tint == .destructive)
    }
}
```

- [ ] **Step 2: 실패 확인 → 최소 구현**

```swift
// Camork/DesignSystem/Components/CamorkButton.swift
import SwiftUI

struct CamorkButton: View {
    enum Role {
        case primary
        case secondary
        case destructive
    }

    /// Color 직접 비교의 불안정성을 회피하기 위한 토큰. View 단에서 Color로 매핑.
    enum TintToken: Equatable {
        case accent          // 강조 — Color.camorkAccent
        case systemDefault   // 시스템 기본 (.bordered가 자동 처리)
        case destructive     // 파괴 — Color.red
    }

    struct ResolvedStyle: Equatable {
        let isProminent: Bool
        let tint: TintToken
    }

    let title: LocalizedStringKey
    let role: Role
    let action: () -> Void

    var body: some View {
        let style = Self.resolveStyle(role)
        return Group {
            if style.isProminent {
                Button(action: action) { label }
                    .buttonStyle(.borderedProminent)
                    .tint(color(for: style.tint))
            } else {
                Button(action: action) { label }
                    .buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
    }

    private var label: some View {
        Text(title)
            .frame(maxWidth: .infinity, minHeight: 44)
    }

    private func color(for token: TintToken) -> Color? {
        switch token {
        case .accent: .camorkAccent
        case .systemDefault: nil   // borderedProminent 분기에서는 호출되지 않음
        case .destructive: .red
        }
    }

    /// 단위 테스트용 — role 분기 로직만 추출.
    static func resolveStyle(_ role: Role) -> ResolvedStyle {
        switch role {
        case .primary:
            return ResolvedStyle(isProminent: true, tint: .accent)
        case .secondary:
            return ResolvedStyle(isProminent: false, tint: .systemDefault)
        case .destructive:
            return ResolvedStyle(isProminent: true, tint: .destructive)
        }
    }
}

#Preview("Dark") {
    VStack(spacing: Spacing.md) {
        CamorkButton(title: "button_share", role: .primary) {}
        CamorkButton(title: "button_cancel", role: .secondary) {}
        CamorkButton(title: "button_delete", role: .destructive) {}
    }
    .padding()
    .background(Color.camorkBackground)
    .preferredColorScheme(.dark)
}

#Preview("Light") {
    VStack(spacing: Spacing.md) {
        CamorkButton(title: "button_share", role: .primary) {}
        CamorkButton(title: "button_cancel", role: .secondary) {}
        CamorkButton(title: "button_delete", role: .destructive) {}
    }
    .padding()
    .background(Color.camorkBackground)
    .preferredColorScheme(.light)
}

#Preview("AX5") {
    VStack(spacing: Spacing.md) {
        CamorkButton(title: "button_share", role: .primary) {}
        CamorkButton(title: "button_cancel", role: .secondary) {}
        CamorkButton(title: "button_delete", role: .destructive) {}
    }
    .padding()
    .background(Color.camorkBackground)
    .dynamicTypeSize(.accessibility5)
    .preferredColorScheme(.dark)
}
```

(momus S3: AX5 Preview / S2: `resolveStyle` 로직 분리 → 단위 테스트 가능 / S6: secondary `.bordered`)

- [ ] **Step 3: 테스트 통과 + Preview 시각 검증** (수동)

```bash
xcodegen generate && \
xcodebuild -scheme Camork \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  test 2>&1 | tail -15
```
Expected: `Test Suite 'CamorkButtonStyleTests' passed`.

Xcode에서 `CamorkButton.swift` 열고 Preview pane → Dark / Light / AX5 모두 정상 렌더링 확인. 다음을 모두 통과해야 함:
- AX5에서 **한국어 "공유하기" 버튼이 잘리지 않고** 줄바꿈 또는 자동 확장 (momus S7).
- **다크 Preview에서 primary(오렌지)와 secondary 버튼의 시각 위계가 명확히 구분**되는지 (재검증 보강 1). 만약 둘 다 오렌지 계열로 보여 위계가 약하면 — `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` 때문에 `.bordered`도 AccentColor를 시스템 기본 tint로 채택 — `CamorkButton`에서 secondary 케이스에 `.tint(.secondary)` 명시 또는 `.tint(Color.gray)` 추가. ResolvedStyle에 `tint: nil` 의도가 흐트러지지 않게 테스트도 갱신.

- [ ] **Step 4: 커밋**

```bash
git add Camork/DesignSystem/Components/CamorkButton.swift
git add CamorkTests/CamorkButtonStyleTests.swift
git commit -F- <<'EOF'
add CamorkButton with HIG-compliant role styling and TintToken-based test surface

화면 내 borderedProminent 1개 원칙(HIG §10)을 따르도록 role별 스타일을 분리한다.
secondary는 .bordered, primary/destructive만 .borderedProminent. tint는 enum
TintToken으로 추상화해 SwiftUI Color 동등 비교의 불안정성을 우회한다.

Constraint: HIG borderedProminent 1개 원칙, SwiftUI Color 동등 비교 회피, 분기 로직은 static resolveStyle로 추출해 단위 테스트 가능
Rejected: 3 role 모두 borderedProminent — primary와 secondary 시각 위계 약화로 HIG 위반
Rejected: ResolvedStyle.tint를 Color?로 두기 — Color 동등 비교 불안정 + 테스트 fragile
Confidence: high
Scope-risk: narrow
Directive: Plan B+ 의 화면 단위 액션 버튼은 모두 본 컴포넌트 사용. 새 role(예: .ghost) 추가 시 TintToken과 ResolvedStyle을 함께 확장하고 테스트 보강.
Tested: CamorkButtonStyleTests의 3 role 분기 (accent / systemDefault / destructive)
Not-tested: AX5 한국어 라벨 시각 잘림 — Preview 시각 검증으로 위임
EOF
```

### Task 8: CamorkCard

**Files:**
- Create: `Camork/DesignSystem/Components/CamorkCard.swift`

(SwiftUI 단위 테스트 없음 — Preview 시각 검증만. 정책 §0 적용.)

- [ ] **Step 1: 구현**

```swift
// Camork/DesignSystem/Components/CamorkCard.swift
import SwiftUI

/// 통일 카드 컨테이너 — 갤러리 세션 카드, 설정 카드 등 카드 UI의 기반.
struct CamorkCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(Spacing.md)
            .background(Color.camorkSecondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    }
}

#Preview("Dark") {
    ZStack {
        Color.camorkBackground.ignoresSafeArea()
        CamorkCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("카드 제목").font(.headline)
                Text("부제목입니다").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Light") {
    ZStack {
        Color.camorkBackground.ignoresSafeArea()
        CamorkCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("카드 제목").font(.headline)
                Text("부제목입니다").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
    .preferredColorScheme(.light)
}

#Preview("AX5") {
    ZStack {
        Color.camorkBackground.ignoresSafeArea()
        CamorkCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("카드 제목").font(.headline)
                Text("부제목입니다").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
    .dynamicTypeSize(.accessibility5)
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: 빌드 확인 + Preview 검증**

```bash
xcodegen generate && \
xcodebuild -scheme Camork \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  build 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`. Xcode Preview에서 Dark/Light/AX5 모두 카드 컨테이너 렌더링 확인.

- [ ] **Step 3: 커밋**

```bash
git add Camork/DesignSystem/Components/CamorkCard.swift
git commit -F- <<'EOF'
add CamorkCard container with continuous corners and elevated surface

세션/사진/설정 카드 UI의 공통 컨테이너. content padding(Spacing.md) + continuous
RoundedRectangle(CornerRadius.lg) + secondarySystemBackground로 카드 UI를 정형화한다.
SwiftUI View 자체의 단위 테스트는 두지 않고 Preview에서 시각 검증한다(테스트 정책 §0).

Constraint: semantic 컬러 + continuous corner 사용, 그림자는 다크/라이트 비대칭 때문에 회피
Rejected: shadow 적용 — 다크모드에서 미미하고 라이트만 시각 차이 커지는 비대칭 발생
Confidence: high
Scope-risk: narrow
Directive: Plan C의 세션 카드 / Plan E의 설정 카드 모두 본 컴포넌트로 wrapping
Tested: Preview Dark/Light/AX5 시각 검증 (Xcode Preview pane)
Not-tested: 자동화된 단위 테스트 — 정책 §0에 따라 Preview에 위임
EOF
```

---

## Phase 5 — 로컬라이제이션 (JSON 직접 작성)

### Task 9: Localizable.xcstrings 작성 (momus C6 — agentic가능)

**Files:**
- Create: `Camork/Resources/Localizable.xcstrings`

- [ ] **Step 1: JSON 작성** (Xcode UI 의존 없이)

`Camork/Resources/Localizable.xcstrings`:
```json
{
  "sourceLanguage" : "ko",
  "strings" : {
    "button_cancel" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Cancel" } },
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "취소" } }
      }
    },
    "button_delete" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Delete" } },
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "삭제" } }
      }
    },
    "button_share" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Share" } },
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "공유하기" } }
      }
    },
    "camera_tab_label" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Camera" } },
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "카메라" } }
      }
    },
    "gallery_tab_label" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Sites" } },
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "현장" } }
      }
    },
    "placeholder_camera_description" : {
      "extractionState" : "manual",
      "comment" : "v1 Core 동안 사용. 출시 전 Plan E에서 최종 카피로 교체 또는 description 제거.",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Coming soon" } },
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "준비 중" } }
      }
    },
    "placeholder_camera_title" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Camera" } },
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "카메라" } }
      }
    },
    "placeholder_gallery_description" : {
      "extractionState" : "manual",
      "comment" : "v1 Core 동안 사용. 출시 전 Plan E에서 최종 카피로 교체 또는 description 제거.",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Coming soon" } },
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "준비 중" } }
      }
    },
    "placeholder_gallery_title" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Sites" } },
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "현장" } }
      }
    },
    "placeholder_settings_description" : {
      "extractionState" : "manual",
      "comment" : "v1 Core 동안 사용. 출시 전 Plan E에서 최종 카피로 교체 또는 description 제거.",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Coming soon" } },
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "준비 중" } }
      }
    },
    "placeholder_settings_title" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Settings" } },
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "설정" } }
      }
    },
    "settings_tab_label" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Settings" } },
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "설정" } }
      }
    }
  },
  "version" : "1.0"
}
```

(Plan B/C/D/E도 같은 스키마로 키 추가. **`sourceLanguage: "ko"` 가 핵심 — 한국어 1차.**)

- [ ] **Step 2: project.yml 확인 — String Catalog 자동 인식**

XcodeGen은 `.xcstrings`를 자동 Resource로 인식 (sources에 포함됨). 별도 설정 불필요.

- [ ] **Step 3: 빌드 + 시뮬레이터 언어 변경 검증** (수동)

```bash
xcodegen generate && \
xcodebuild -scheme Camork \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  build 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`.

Xcode ⌘R → 시뮬레이터에서:
- 한국어 시스템: 탭 "카메라 / 현장 / 설정"
- 시뮬레이터 → 설정 → 일반 → 언어 → English → 앱 재실행: "Camera / Sites / Settings"

- [ ] **Step 4: 커밋**

```bash
git add Camork/Resources/Localizable.xcstrings
git commit -F- <<'EOF'
add Korean-first String Catalog with 12 initial keys for tabs and placeholders

한국어 1차 + 영어 번역 동봉이라는 정체성을 코드 차원에 박는다. .xcstrings JSON을
직접 작성해 Xcode GUI 의존을 제거했고, sourceLanguage: ko로 한국어를 1차로 명시한다.
placeholder description은 "준비 중 / Coming soon" 중립 카피로 시작해 출시 전 교체할
필요를 줄였다.

Constraint: sourceLanguage: "ko", SwiftUI LocalizedStringKey 자동 lookup 호환, 사용자 노출 카피는 내부 plan 명칭(Plan B/C/E) 금지
Rejected: String(localized:) 호출 — LocalizedStringKey와 일관성 흔들림
Rejected: "Implementing in Plan X" 영문 카피 — 내부 plan 명칭이 사용자 화면 노출
Confidence: high
Scope-risk: narrow
Directive: Plan B+ 의 새 텍스트는 모두 본 catalog에 키로 추가. 추가 언어(중/일 등)는 v2 Trust 단계에서.
Tested: 시뮬레이터 시스템 언어 한↔영 전환 시 라벨 변경 확인
Not-tested: 추가 언어 — v2 Trust 단계로 위임
EOF
```

---

## Phase 6 — 마무리 검증 + Plan B 인계

### Task 10: 전체 회귀 + 수동 검증 (momus S7 한국어 잘림 포함)

- [ ] **Step 1: 클린 빌드 + 전체 테스트**

```bash
xcodegen generate && \
xcodebuild clean -scheme Camork && \
xcodebuild -scheme Camork \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  test 2>&1 | tail -25
```
Expected:
- `BUILD SUCCEEDED`
- `Test Suite 'All tests' passed` (ThemeTests + ColorsTests + CamorkButtonStyleTests)
- 0 failures

- [ ] **Step 2: 시뮬레이터 수동 체크리스트**

iPhone 16 Pro 시뮬레이터에서 ⌘R 후:
- [ ] 다크모드 시스템에서 다크 톤으로 뜸 (배경 검정 계열)
- [ ] 라이트모드 시스템(시뮬레이터 ⇧⌘A)에서 라이트 톤으로 깨끗하게 변환됨
- [ ] 3개 탭(카메라/현장/설정) 보임, SF Symbol 정상
- [ ] 탭 전환 정상
- [ ] 각 placeholder 텍스트 (한국어) 잘림 없음
- [ ] **시뮬레이터 언어 영어로 변경 → 탭 라벨 "Camera / Sites / Settings"** (momus C6 검증)
- [ ] **한국어 + Dynamic Type AX5에서 탭 라벨 잘림 없음** (momus S7)
  - 시뮬레이터 → 설정 → 디스플레이 → 텍스트 크기 → 가장 큼
- [ ] AX5 + RootTabView Preview에서 placeholder 본문 안 깨짐 (Xcode Preview)
- [ ] Xcode에서 `CamorkButton.swift` Preview → 3 role 다크/라이트/AX5 모두 정상

- [ ] **Step 3: 한 가지 누락 발견 시** 해당 task로 돌아가서 수정 → 다시 회귀 → Step 2 재실행

### Task 11: Plan A 완료 보고서

**Files:**
- Create: `docs/superpowers/reports/2026-05-19-plan-A-setup-complete.md`

- [ ] **Step 1: 작성**

```markdown
# Plan A 완료 보고서

- 완료일: YYYY-MM-DD (실제 완료일로 교체)
- 산출: 빌드되는 빈 SwiftUI 앱 + 디자인 토큰 + 기본 컴포넌트 + 한/영 + 백그라운드 가림막 hook

## 검증 결과
- 빌드: SUCCEEDED
- 테스트: ThemeTests / ColorsTests / CamorkButtonStyleTests 모두 PASS
- 시뮬레이터 수동 검증: 위 체크리스트 모두 통과 (다크/라이트, 한/영, AX5)

## Plan B 진입 전 결정/확인 필요 (인계)

(momus S4 + Spec §15 오픈 이슈에서 가져온 항목들)

1. **entitlements 확정** — `AVFoundation` 자체는 entitlement 불필요하지만, Background mode (카메라 백그라운드 캡처?) 사용 여부 결정.
2. **메타데이터 영속 방식** — SQLite (GRDB) vs JSON 파일. Spec §15. Plan B 시작 전 결정 필요.
3. **AVFoundation 동시성 패턴** — `actor MediaStorage` / `actor SessionManager` 의 Swift Testing `await` 검증 패턴 합의.
4. **HEIC vs JPEG** — Spec §6.5에서 HEIC 기본 채택. 변경 시 Plan B에서 반영.
5. **CoreLocation 권한 요청 시점** — Spec §15. 앱 첫 실행 vs 첫 촬영 vs 설정 명시.
6. **실기기 빌드 시 사이닝 재정렬** — 현재 `CODE_SIGN_STYLE: Automatic` + `CODE_SIGNING_ALLOWED=NO` 조합은 시뮬레이터 전용. 실기기/TestFlight/App Store 배포 시 `DEVELOPMENT_TEAM` 설정 + 사이닝 옵션 재정렬 필요.
7. **AVFoundation TDD 한계 정책** — `AVCaptureSession`은 시뮬레이터에서 캡처 제한. configuration 빌더(노출/포커스 설정 함수)는 단위 테스트하고, 실제 캡처는 실기기 시각 검증으로 분기. Plan B 정책 §0에 보강 추가 필요.
8. **동시성 ADR (Plan B 첫 task)** — `actor MediaStorage`/`actor SessionManager`의 reentrancy 정책, `@MainActor` UI ↔ actor 도메인 경계, 의존성 주입 패턴 (테스트가 actor 인스턴스를 어떻게 격리할지), AVFoundation 백그라운드 큐 ↔ actor 모델 충돌 검토. Plan B 진입 시 첫 task로 ADR 작성.
9. **placeholder 영어 카피 출시 전 교체** — `placeholder_*_description`의 "Implementing in Plan B/C/E." 영문 카피는 내부 plan 명칭이 사용자에게 노출됨. 출시 전(Plan E) 사용자 친화 카피로 교체 (예: "Coming soon" 또는 빈 description).

## 미해결 (출시 전 결정)
- **AccentColor 정확 hex** — 현재 `#FF9500` (라이트) / `#FF9F00` (다크) 임시. frontend-design 단계 또는 디자이너 입력 필요.
- **App Icon 1024x1024** — Plan E에서 추가.
- **백그라운드 가림막** — Plan E에서 `AppBackgroundShield` 실구현.

## 다음 단계
Plan B (Storage + Sessions + Camera) 작성으로 진입. 위 9개 인계 항목을 brainstorming/시작 시 정렬.
```

- [ ] **Step 2: 커밋**

```bash
git add docs/superpowers/reports/2026-05-19-plan-A-setup-complete.md
git commit -F- <<'EOF'
add Plan A completion report with nine Plan B handoff items

Plan A의 산출과 회귀 검증 결과, 그리고 Plan B 진입 시 결정해야 할 9개 인계 항목을
정리한다. 다음 plan 작성자가 brainstorming/spec/Plan A의 결정 컨텍스트를 잃지 않게
하고, 미해결과 출시 전 결정 사항도 분리해 둔다.

Constraint: 9개 인계 항목 명시(entitlements / 영속 / 동시성 / HEIC / 위치 권한 / 실기기 사이닝 / AVFoundation TDD 한계 / actor ADR / placeholder 영문 카피), 출시 전 결정은 별도 섹션
Rejected: 자유 형식 노트 — 다음 plan 작성자가 항목 누락 가능
Confidence: high
Scope-risk: narrow
Directive: Plan B 작성 첫 task로 인계 항목 정렬 ADR을 작성
Tested: 빌드/테스트 회귀 결과 + 시뮬레이터 수동 체크리스트 첨부 (보고서 본문)
Not-tested: 보고서 자체는 빌드 산출물 아님
EOF
```

---

## Plan A 완료 체크리스트

- [ ] Task 0: 환경 점검 (XcodeGen, 시뮬레이터, .gitignore)
- [ ] Task 1: `project.yml` (momus C1/C2/C3/C9 정합)
- [ ] Task 2: 디렉토리 + entitlements + Asset Catalog (AccentColor 라이트/다크 명시)
- [ ] Task 3: `AppBackgroundShield` placeholder hook
- [ ] Task 4: `CamorkApp` + `RootTabView` + 3 placeholder (`LocalizedStringKey` 직접)
- [ ] Task 5: Theme.swift (Spacing/CornerRadius) + 테스트 통과
- [ ] Task 6: Colors.swift + 라이트/다크 trait 검증 테스트 통과
- [ ] Task 7: CamorkButton (역할별 분기 + HIG 준수 + 단위 테스트)
- [ ] Task 8: CamorkCard (Preview 시각 검증)
- [ ] Task 9: Localizable.xcstrings (JSON 직접)
- [ ] Task 10: 클린 회귀 + 수동 체크리스트 전체 통과
- [ ] Task 11: 완료 보고서 + Plan B 인계

**모두 통과 시 → Plan B 작성 단계.**

---

## 자주 쓰는 명령 (CODE_SIGNING 옵션 통일)

```bash
# project.yml 수정 후 매번
xcodegen generate

# 빌드만
xcodebuild -scheme Camork \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  build 2>&1 | tail -20

# 테스트
xcodebuild -scheme Camork \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  test 2>&1 | tail -20

# 클린
xcodebuild clean -scheme Camork
```

`iPhone 16 Pro`가 없으면 `iPhone 15 Pro`로 치환. `xcrun simctl list devices available`로 확인.

---

## 참고

- 부모 가이드: `/Users/jedel/Projects/CLAUDE.md`
- HIG 시각 가이드: `/Users/jedel/Projects/.claude/references/apple-hig.md`
- 앱 가이드: `/Users/jedel/Projects/camork-ios/CLAUDE.md`
- 설계서: `docs/superpowers/specs/2026-05-19-camork-rebuild-design.md`

---

## 부록 A — 리뷰 피드백 ↔ 반영 위치

### v2 (momus 16 항목)

| momus 항목 | 반영 위치 |
|---|---|
| **C1** Info.plist 충돌 | Task 1 `sources.excludes: Info.plist` + Task 1 Step 3 자동 생성 확인 |
| **C2** `INFOPLIST_KEY_UILaunchScreen_Generation` 무효 | Task 1 — 해당 라인 삭제 |
| **C3** `BUNDLE_LOADER`/`TEST_HOST` 수동 | Task 1 — XcodeGen 자동 위임 |
| **C4** Swift Testing host app 검증 누락 | Task 5 Step 2/4 — 실제 시뮬레이터 부팅 확인 |
| **C5** AccentColor JSON appearances 누락 + toy 테스트 | Task 2 Step 3 (라이트/다크 명시) + Task 6 Step 1 (UIColor trait 검증) |
| **C6** String Catalog GUI 의존 | Task 9 — JSON 직접 작성 + 정확한 스키마 inline |
| **C7** `String(localized:)` 충돌 | Task 4 — `LocalizedStringKey` 직접 사용 (`Label("key", systemImage:)`) |
| **C8** 시뮬레이터 가용성 | Task 0 Step 2 — 사전 확인 + destination 통일 (`iPhone 16 Pro`) |
| **C9** 코드사이닝 옵션 | 모든 xcodebuild 명령에 `CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""` |
| **S1** `.gitignore` sanity check | Task 0 Step 3 |
| **S2** SwiftUI 테스트 정책 | 문서 상단 "SwiftUI 테스트 정책" + Task 7 `resolveStyle` 로직 분리 |
| **S3** Dynamic Type AX5 Preview | Task 4 Step 2 / Task 7 Step 2 / Task 8 Step 1 |
| **S4** entitlements 인계 | Task 11 보고서 항목 1 |
| **S5** `UIUserInterfaceStyle: Dark` 강제와 라이트 검증 모순 | Task 1 — 강제 다크 제거, 시스템 따라감 |
| **S6** `borderedProminent` HIG 위반 | Task 7 — secondary `.bordered` |
| **S7** 한국어 라벨 잘림 검증 | Task 10 Step 2 체크리스트 + Task 7 AX5 Preview |

### v3 (추가 critic 9 항목)

| 항목 | 반영 위치 |
|---|---|
| **C1** AGENTS.md Lore Commit Protocol | 문서 상단 "Commit Policy" 섹션 + 7개 commit 예시 전부 Lore 형식으로 교체 (Task 4/5/6/7/8/9/11) |
| **C2** `Color` 동등 비교 불안정 → `TintToken` enum | Task 7 — `ResolvedStyle.tint: TintToken`, View 단에서 `color(for:)`로 Color 매핑 |
| **C3** `swift test` 표기 오류 | "완료 기준" — `xcodebuild test`로 정정, `swift test` 사용 안 함 명시 |
| **C4** tracked `Info.plist`는 `.gitignore` 무효 | Task 0 Step 3 — `git ls-files` 확인 + `git rm --cached` 절차 추가 |
| **C5** "위 5개 인계 항목" → "위 9개" | 보고서 본문 — "위 9개"로 수정 (Spec §15/§6.5 참조는 정확하여 유지) |
| **S1** Task 3 빌드 실패가 정상 단계 — 혼란 | Task 3 Step 2 — 빌드 명령 제거, Task 4에서 통합 빌드 검증 |
| **S2** placeholder 영문 카피 "Implementing in Plan X" | Task 9 — `Coming soon` / `준비 중`으로 처음부터 중립, comment에 출시 전 교체 가이드 |
| **S3** `sed` plan 본문 치환 → 기록 오염 | Task 0 Step 2 — `CAMORK_SIM` 환경변수 방식만 남김, plan 문서 자체 치환 금지 |
| **S4** `UIColor(named:)` bundle lookup 견고화 | Task 6 — `Bundle(for: BundleToken.self)` 명시, named/in/compatibleWith API 사용 |
